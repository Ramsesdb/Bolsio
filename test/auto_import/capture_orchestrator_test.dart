import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/pending_import/pending_import_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/models/account/account.dart';
import 'package:bolsio/core/models/auto_import/capture_channel.dart';
import 'package:bolsio/core/models/auto_import/raw_capture_event.dart';
import 'package:bolsio/core/services/auto_import/capture/capture_source.dart';
import 'package:bolsio/core/services/auto_import/dedupe/dedupe_checker.dart';
import 'package:bolsio/core/services/auto_import/orchestrator/capture_orchestrator.dart';

/// A fake capture source for testing that emits controlled events.
class FakeCaptureSource implements CaptureSource {
  final StreamController<RawCaptureEvent> _controller =
      StreamController<RawCaptureEvent>.broadcast();

  final CaptureChannel _channel;

  FakeCaptureSource({CaptureChannel channel = CaptureChannel.sms})
      : _channel = channel;

  @override
  CaptureChannel get channel => _channel;

  @override
  Stream<RawCaptureEvent> get events => _controller.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  /// Emit a test event.
  void emit(RawCaptureEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}

AppDB _createTestDb() {
  return AppDB.forTesting(NativeDatabase.memory());
}

Future<void> _insertAccount(
  AppDB db, {
  required String id,
  required String name,
  String currencyId = 'VES',
}) async {
  await db.into(db.currencies).insertOnConflictUpdate(CurrenciesCompanion(
        code: Value(currencyId),
        symbol: const Value('Bs.'),
        name: const Value('Bolivar'),
        decimalPlaces: const Value(2),
        isDefault: const Value(false),
        type: const Value(0),
      ));

  await db.into(db.accounts).insert(AccountsCompanion(
        id: Value(id),
        name: Value(name),
        iniValue: const Value(0),
        date: Value(DateTime(2026, 1, 1)),
        type: const Value(AccountType.normal),
        iconId: const Value('money'),
        displayOrder: const Value(0),
        currencyId: Value(currencyId),
      ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDB db;
  late PendingImportService pendingImportService;
  late DedupeChecker dedupeChecker;
  late CaptureOrchestrator orchestrator;
  late FakeCaptureSource fakeSource;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    db = _createTestDb();
    await db.customStatement('PRAGMA foreign_keys = OFF');
    pendingImportService = PendingImportService.forTesting(db);
    dedupeChecker = DedupeChecker.forTesting(
      db: db,
      pendingImportService: pendingImportService,
    );
    orchestrator = CaptureOrchestrator.forTesting(
      db: db,
      pendingImportService: pendingImportService,
      dedupeChecker: dedupeChecker,
    );
    fakeSource = FakeCaptureSource();
  });

  tearDown(() async {
    await orchestrator.stop();
    fakeSource.dispose();
    await db.close();
  });

  group('CaptureOrchestrator', () {
    test('event with unknown sender produces no pending_import', () async {
      await _insertAccount(db,
          id: 'acc-bdv', name: 'Banco de Venezuela');

      await orchestrator.registerSource(fakeSource);
      await orchestrator.start();

      // Emit an event with an unknown sender
      fakeSource.emit(RawCaptureEvent(
        rawText:
            'Recibiste un PagomovilBDV por Bs. 900,00 del 0412-7635070 Ref: 002103869591 en fecha: 25-01-25 hora: 21:26',
        sender: '9999', // unknown sender
        receivedAt: DateTime.now(),
        channel: CaptureChannel.sms,
      ));

      // Give the async handler time to complete
      await Future.delayed(const Duration(milliseconds: 100));

      final imports = await pendingImportService.getPendingImports().first;
      expect(imports, isEmpty);
    });

    test('event with sender 2661 but non-parseable text (OTP) produces no pending_import',
        () async {
      await _insertAccount(db,
          id: 'acc-bdv', name: 'Banco de Venezuela');

      await orchestrator.registerSource(fakeSource);
      await orchestrator.start();

      fakeSource.emit(RawCaptureEvent(
        rawText:
            'BDV: La clave de pago para procesar tu operacion es 67928761',
        sender: '2661',
        receivedAt: DateTime.now(),
        channel: CaptureChannel.sms,
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      final imports = await pendingImportService.getPendingImports().first;
      expect(imports, isEmpty);
    });

    test('valid SMS event produces exactly 1 pending_import with status=pending',
        () async {
      await _insertAccount(db,
          id: 'acc-bdv', name: 'Banco de Venezuela');

      await orchestrator.registerSource(fakeSource);
      await orchestrator.start();

      fakeSource.emit(RawCaptureEvent(
        rawText:
            'Recibiste un PagomovilBDV por Bs. 900,00 del 0412-7635070 Ref: 002103869591 en fecha: 25-01-25 hora: 21:26',
        sender: '2661',
        receivedAt: DateTime.now(),
        channel: CaptureChannel.sms,
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      final imports = await pendingImportService.getPendingImports().first;
      expect(imports, hasLength(1));
      expect(imports.first.status, 'pending');
      expect(imports.first.amount, 900.0);
      expect(imports.first.bankRef, '002103869591');
      expect(imports.first.accountId, 'acc-bdv');
    });

    test('duplicate event (same bankRef) is skipped and does not create a new pending_import',
        () async {
      await _insertAccount(db,
          id: 'acc-bdv', name: 'Banco de Venezuela');

      await orchestrator.registerSource(fakeSource);
      await orchestrator.start();

      // First event — should be pending
      fakeSource.emit(RawCaptureEvent(
        rawText:
            'Recibiste un PagomovilBDV por Bs. 900,00 del 0412-7635070 Ref: 002103869591 en fecha: 25-01-25 hora: 21:26',
        sender: '2661',
        receivedAt: DateTime.now(),
        channel: CaptureChannel.sms,
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      // Second event — same bankRef, should be detected as duplicate
      fakeSource.emit(RawCaptureEvent(
        rawText:
            'Recibiste un PagomovilBDV por Bs. 900,00 del 0412-7635070 Ref: 002103869591 en fecha: 25-01-25 hora: 21:26',
        sender: '2661',
        receivedAt: DateTime.now(),
        channel: CaptureChannel.sms,
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      final imports = await pendingImportService.getPendingImports().first;
      // Current orchestrator behavior: duplicates are skipped early and
      // therefore do not create additional pending rows.
      expect(imports, hasLength(1));
      expect(imports.first.status, 'pending');
      expect(imports.first.bankRef, '002103869591');
    });
  });

  group('CaptureOrchestrator — profile toggle filter', () {
    test(
        'event that matches a disabled profile produces no pending_import',
        () async {
      await _insertAccount(db, id: 'acc-bdv', name: 'Banco de Venezuela');

      // Disable the bdv_sms profile by writing '0' into the global state map
      // (the same map that UserSettingService.isProfileEnabled reads from).
      appStateSettings[SettingKey.bdvSmsProfileEnabled] = '0';

      await orchestrator.registerSource(fakeSource);
      await orchestrator.start();

      // Emit a valid BDV Pagomovil SMS that would normally produce a proposal.
      fakeSource.emit(RawCaptureEvent(
        rawText:
            'Recibiste un PagomovilBDV por Bs. 500,00 del 0412-1234567 Ref: 001122334455 en fecha: 22-04-26 hora: 10:00',
        sender: '2661',
        receivedAt: DateTime.now(),
        channel: CaptureChannel.sms,
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      final imports = await pendingImportService.getPendingImports().first;
      expect(imports, isEmpty,
          reason: 'Profile bdv_sms is disabled — proposal must be filtered');

      // Restore global state so subsequent tests are not affected.
      appStateSettings.remove(SettingKey.bdvSmsProfileEnabled);
    });
  });

  group('CaptureOrchestrator — notification channel (Tanda 3A)', () {
    late FakeCaptureSource fakeNotifSource;

    setUp(() {
      fakeNotifSource =
          FakeCaptureSource(channel: CaptureChannel.notification);
    });

    tearDown(() {
      fakeNotifSource.dispose();
    });

    test(
        'valid BDV notification event from allowlisted package produces 1 pending_import',
        () async {
      await _insertAccount(db,
          id: 'acc-bdv', name: 'Banco de Venezuela');

      await orchestrator.registerSource(fakeNotifSource);
      await orchestrator.start();

      // Emit a valid BDV transferencia recibida notification
      fakeNotifSource.emit(RawCaptureEvent(
        rawText:
            'Transferencia BDV recibida\n"Recibiste una transferencia BDV de JOINER ALEXANDER ROVARIO SAAVEDRA por Bs.277.000,00 bajo el número de operación 059135723999"',
        sender: 'com.bancodevenezuela.bdvdigital', // Must match BdvNotifProfile.knownSenders
        receivedAt: DateTime(2026, 4, 15, 14, 36),
        channel: CaptureChannel.notification,
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      final imports = await pendingImportService.getPendingImports().first;
      expect(imports, hasLength(1));
      expect(imports.first.status, 'pending');
      expect(imports.first.amount, 277000.0);
      expect(imports.first.bankRef, '059135723999');
      expect(imports.first.accountId, 'acc-bdv');
      expect(imports.first.channel, 'notification');
    });

    test(
        'notification event from non-allowlisted package produces 0 pending_imports',
        () async {
      await _insertAccount(db,
          id: 'acc-bdv', name: 'Banco de Venezuela');

      await orchestrator.registerSource(fakeNotifSource);
      await orchestrator.start();

      // Emit from an unknown package — not in any profile's knownSenders
      fakeNotifSource.emit(RawCaptureEvent(
        rawText:
            'Transferencia BDV recibida\n"Recibiste una transferencia BDV de JOINER ALEXANDER ROVARIO SAAVEDRA por Bs.277.000,00 bajo el número de operación 059135723999"',
        sender: 'com.unknown.app', // NOT in BdvNotifProfile.knownSenders
        receivedAt: DateTime(2026, 4, 15, 14, 36),
        channel: CaptureChannel.notification,
      ));

      await Future.delayed(const Duration(milliseconds: 100));

      final imports = await pendingImportService.getPendingImports().first;
      expect(imports, isEmpty);
    });
  });
}
