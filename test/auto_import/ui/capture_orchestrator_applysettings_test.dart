import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';
import 'package:wallex/core/services/auto_import/capture/capture_source.dart';
import 'package:wallex/core/services/auto_import/dedupe/dedupe_checker.dart';
import 'package:wallex/core/services/auto_import/orchestrator/capture_orchestrator.dart';

/// A fake capture source for testing that can be configured per-channel.
class _FakeCaptureSource implements CaptureSource {
  final StreamController<RawCaptureEvent> _controller =
      StreamController<RawCaptureEvent>.broadcast();
  final CaptureChannel _channel;
  final bool _hasPermission;

  _FakeCaptureSource({
    required CaptureChannel channel,
    bool hasPermission = true,
  })  : _channel = channel,
        _hasPermission = hasPermission;

  @override
  CaptureChannel get channel => _channel;

  @override
  Stream<RawCaptureEvent> get events => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> hasPermission() async => _hasPermission;

  @override
  Future<bool> requestPermission() async => _hasPermission;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void dispose() => _controller.close();
}

AppDB _createTestDb() => AppDB.forTesting(NativeDatabase.memory());

void main() {
  late AppDB db;
  late PendingImportService pendingService;
  late DedupeChecker dedupeChecker;

  setUp(() async {
    db = _createTestDb();
    pendingService = PendingImportService.forTesting(db);
    dedupeChecker = DedupeChecker.forTesting(
      db: db,
      pendingImportService: pendingService,
    );

    // Clear the global settings map before each test
    appStateSettings.clear();
  });

  tearDown(() async {
    await db.close();
    appStateSettings.clear();
  });

  group('CaptureOrchestrator.applySettings', () {
    test('autoImportEnabled=false results in 0 sources', () async {
      appStateSettings[SettingKey.autoImportEnabled] = '0';

      final orchestrator = CaptureOrchestrator.forTesting(
        db: db,
        pendingImportService: pendingService,
        dedupeChecker: dedupeChecker,
      );

      await orchestrator.applySettings(
        sourceFactory: (_) async =>
            _FakeCaptureSource(channel: CaptureChannel.sms),
      );

      expect(orchestrator.sources, isEmpty);
    });

    test(
        'autoImportEnabled=true + binanceApiEnabled=true + hasCredentials '
        'registers 1 Binance source', () async {
      appStateSettings[SettingKey.autoImportEnabled] = '1';
      appStateSettings[SettingKey.smsImportEnabled] = '0';
      appStateSettings[SettingKey.notifListenerEnabled] = '0';
      appStateSettings[SettingKey.binanceApiEnabled] = '1';

      final orchestrator = CaptureOrchestrator.forTesting(
        db: db,
        pendingImportService: pendingService,
        dedupeChecker: dedupeChecker,
      );

      // The sourceFactory simulates that Binance has credentials
      await orchestrator.applySettings(
        sourceFactory: (channel) async {
          return _FakeCaptureSource(
            channel: channel,
            hasPermission: true,
          );
        },
      );

      // Only Binance API should be registered (SMS and Notif are disabled)
      // Note: on non-Android platforms, SMS/Notif are skipped by Platform.isAndroid check
      // In test environment, Platform.isAndroid may be false, so only Binance registers
      expect(orchestrator.sources.length, 1);
      expect(orchestrator.sources.first.channel, CaptureChannel.api);
    });

    test(
        'autoImportEnabled=true + smsEnabled=true + no permission '
        'results in 0 SMS sources', () async {
      appStateSettings[SettingKey.autoImportEnabled] = '1';
      appStateSettings[SettingKey.smsImportEnabled] = '1';
      appStateSettings[SettingKey.notifListenerEnabled] = '0';
      appStateSettings[SettingKey.binanceApiEnabled] = '0';

      final orchestrator = CaptureOrchestrator.forTesting(
        db: db,
        pendingImportService: pendingService,
        dedupeChecker: dedupeChecker,
      );

      // Note: Platform.isAndroid is false in test environment,
      // so SMS source won't even be attempted.
      await orchestrator.applySettings(
        sourceFactory: (channel) async {
          return _FakeCaptureSource(
            channel: channel,
            hasPermission: false, // no permission
          );
        },
      );

      // On non-Android platforms, SMS is skipped entirely
      expect(orchestrator.sources, isEmpty);
    });

    test('clearSources stops and removes all sources', () async {
      appStateSettings[SettingKey.autoImportEnabled] = '1';
      appStateSettings[SettingKey.binanceApiEnabled] = '1';
      appStateSettings[SettingKey.smsImportEnabled] = '0';
      appStateSettings[SettingKey.notifListenerEnabled] = '0';

      final orchestrator = CaptureOrchestrator.forTesting(
        db: db,
        pendingImportService: pendingService,
        dedupeChecker: dedupeChecker,
      );

      await orchestrator.applySettings(
        sourceFactory: (channel) async => _FakeCaptureSource(
          channel: channel,
          hasPermission: true,
        ),
      );

      expect(orchestrator.sources, isNotEmpty);

      await orchestrator.clearSources();
      expect(orchestrator.sources, isEmpty);
    });

    test('applySettings reconfigures sources on successive calls', () async {
      final orchestrator = CaptureOrchestrator.forTesting(
        db: db,
        pendingImportService: pendingService,
        dedupeChecker: dedupeChecker,
      );

      // First call: enable Binance
      appStateSettings[SettingKey.autoImportEnabled] = '1';
      appStateSettings[SettingKey.smsImportEnabled] = '0';
      appStateSettings[SettingKey.notifListenerEnabled] = '0';
      appStateSettings[SettingKey.binanceApiEnabled] = '1';

      await orchestrator.applySettings(
        sourceFactory: (channel) async => _FakeCaptureSource(
          channel: channel,
          hasPermission: true,
        ),
      );
      expect(orchestrator.sources.length, 1);

      // Second call: disable everything
      appStateSettings[SettingKey.autoImportEnabled] = '0';

      await orchestrator.applySettings(
        sourceFactory: (channel) async => _FakeCaptureSource(
          channel: channel,
          hasPermission: true,
        ),
      );
      expect(orchestrator.sources, isEmpty);
    });
  });
}
