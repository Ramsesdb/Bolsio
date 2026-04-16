import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/auto_import/background/local_notification_service.dart';
import 'package:wallex/core/services/auto_import/orchestrator/capture_orchestrator.dart';

/// Manages the Android foreground service that keeps auto-import capture
/// running when the app is closed.
///
/// Uses the `flutter_background_service` plugin to run a persistent foreground
/// service with a notification on the [LocalNotificationService.captureChannelId]
/// channel.
///
/// The background isolate re-initializes the database and orchestrator
/// independently from the main isolate.
class WallexBackgroundService {
  static final WallexBackgroundService instance = WallexBackgroundService._();

  WallexBackgroundService._();

  /// For testing: create an instance with a custom service.
  WallexBackgroundService.forTesting({
    FlutterBackgroundService? service,
  }) : _serviceOverride = service;

  FlutterBackgroundService? _serviceOverride;

  FlutterBackgroundService get _service =>
      _serviceOverride ?? FlutterBackgroundService();

  bool _initialized = false;

  /// Configure the background service.
  ///
  /// Must be called once during app startup (in main.dart).
  /// Does NOT start the service — call [startService] for that.
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          foregroundServiceNotificationId:
              LocalNotificationService.foregroundNotificationId,
          notificationChannelId:
              LocalNotificationService.captureChannelId,
          initialNotificationTitle: 'Wallex',
          initialNotificationContent: 'Capturando movimientos bancarios',
          foregroundServiceTypes: [AndroidForegroundType.specialUse],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
        ),
      );

      _initialized = true;
      debugPrint(
        'WallexBackgroundService: configured',
      );
    } catch (e) {
      debugPrint(
        'WallexBackgroundService: Failed to configure: $e',
      );
    }
  }

  /// Start the background service (only if auto-import is enabled).
  ///
  /// The service shows a persistent foreground notification and keeps
  /// SMS, notification, and API polling sources alive.
  Future<void> startService() async {
    if (!_initialized) return;

    final isRunning = await _service.isRunning();
    if (isRunning) {
      debugPrint(
        'WallexBackgroundService: Background service already running — skipping start',
      );
      return;
    }

    try {
      await _service.startService();
      debugPrint(
        'WallexBackgroundService: Background service started',
      );
    } catch (e) {
      debugPrint(
        'WallexBackgroundService: Failed to start background service: $e',
      );
    }
  }

  /// Stop the background service.
  Future<void> stopService() async {
    if (!_initialized) return;

    final isRunning = await _service.isRunning();
    if (!isRunning) return;

    try {
      _service.invoke('stop');
      debugPrint(
        'WallexBackgroundService: Background service stop requested',
      );
    } catch (e) {
      debugPrint(
        'WallexBackgroundService: Failed to stop background service: $e',
      );
    }
  }

  /// Send a restart command to the background service.
  ///
  /// Used when the user changes channel settings or Binance credentials
  /// so the orchestrator reconfigures its sources.
  Future<void> restartOrchestrator() async {
    if (!_initialized) return;

    final isRunning = await _service.isRunning();
    if (!isRunning) return;

    try {
      _service.invoke('restart');
      debugPrint(
        'WallexBackgroundService: Background service restart requested',
      );
    } catch (e) {
      debugPrint(
        'WallexBackgroundService: Failed to restart background service: $e',
      );
    }
  }

  /// Whether the background service is currently running.
  Future<bool> isRunning() async {
    if (!_initialized) return false;
    return _service.isRunning();
  }
}

/// Entry point for the background isolate.
///
/// This function runs in a SEPARATE isolate from the main app. It must
/// re-initialize all dependencies (Flutter bindings, database, settings)
/// because singletons from the main isolate are NOT shared.
@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  // Initialize Flutter bindings in the background isolate
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint(
    'WallexBackgroundService: Background isolate started',
  );

  // Initialize settings so the orchestrator can read toggle states
  try {
    await UserSettingService.instance.initializeGlobalStateMap();
  } catch (e) {
    debugPrint(
      'WallexBackgroundService: Failed to init settings in background: $e',
    );
  }

  // Initialize local notifications for showing "pending" alerts
  final localNotif = LocalNotificationService.instance;
  try {
    await localNotif.initialize();
  } catch (e) {
    debugPrint(
      'WallexBackgroundService: Failed to init local notifications in background: $e',
    );
  }

  // Set up the capture orchestrator with a callback for new pending imports
  final orchestrator = CaptureOrchestrator.instance;

  // Wire the onNewPendingImport callback to show local notifications
  orchestrator.onNewPendingImport = (int pendingCount) async {
    try {
      await localNotif.showNewPendingNotification(pendingCount);
    } catch (e) {
      debugPrint(
        'WallexBackgroundService: Error showing pending notification: $e',
      );
    }
  };

  // Apply settings and start capturing
  try {
    await orchestrator.applySettings();
    debugPrint(
      'WallexBackgroundService: Orchestrator started in background isolate',
    );
  } catch (e) {
    debugPrint(
      'WallexBackgroundService: Failed to start orchestrator in background: $e',
    );
  }

  // Listen for commands from the main isolate
  service.on('stop').listen((event) async {
    debugPrint(
      'WallexBackgroundService: Received stop command',
    );
    await orchestrator.stop();
    await service.stopSelf();
  });

  service.on('restart').listen((event) async {
    debugPrint(
      'WallexBackgroundService: Received restart command — reconfiguring orchestrator',
    );
    // Re-read settings (they may have changed in the main isolate's DB)
    try {
      await UserSettingService.instance.initializeGlobalStateMap();
      await orchestrator.applySettings();
    } catch (e) {
      debugPrint(
        'WallexBackgroundService: Error restarting orchestrator: $e',
      );
    }
  });

  // If running as foreground service, update the notification
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();

    await service.setForegroundNotificationInfo(
      title: 'Wallex',
      content: 'Capturando movimientos bancarios',
    );
  }
}
