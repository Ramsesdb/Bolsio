import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/models/auto_import/capture_channel.dart';
import 'package:nitido/core/services/auto_import/background/local_notification_service.dart';
import 'package:nitido/core/services/auto_import/orchestrator/capture_orchestrator.dart';

/// Manages the Android foreground service that keeps auto-import capture
/// running when the app is closed.
///
/// Uses the `flutter_background_service` plugin to run a persistent foreground
/// service with a notification on the [LocalNotificationService.captureChannelId]
/// channel.
///
/// The background isolate re-initializes the database and orchestrator
/// independently from the main isolate.
class NitidoBackgroundService {
  static final NitidoBackgroundService instance = NitidoBackgroundService._();

  NitidoBackgroundService._();

  /// For testing: create an instance with a custom service.
  NitidoBackgroundService.forTesting({
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
          // Boot-start is handled by our own BootReceiver (BootReceiver.kt),
          // which is whitelisted under the app's package and survives MIUI's
          // OEM autostart pruning better than the plugin's internal receiver.
          // Keeping this false prevents the plugin from firing its own internal
          // BroadcastReceiver on cold-start, which was competing with the main
          // engine during the first-frame window and causing a UI freeze.
          autoStartOnBoot: false,
          isForegroundMode: true,
          foregroundServiceNotificationId:
              LocalNotificationService.foregroundNotificationId,
          notificationChannelId:
              LocalNotificationService.captureChannelId,
          initialNotificationTitle: 'Nitido',
          initialNotificationContent: 'Capturando movimientos bancarios',
          foregroundServiceTypes: [AndroidForegroundType.specialUse],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
        ),
      );

      _initialized = true;
      debugPrint(
        'NitidoBackgroundService: configured',
      );
    } catch (e) {
      debugPrint(
        'NitidoBackgroundService: Failed to configure: $e',
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
        'NitidoBackgroundService: Background service already running — skipping start',
      );
      return;
    }

    try {
      await _service.startService();
      debugPrint(
        'NitidoBackgroundService: Background service started',
      );
    } catch (e) {
      debugPrint(
        'NitidoBackgroundService: Failed to start background service: $e',
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
        'NitidoBackgroundService: Background service stop requested',
      );
    } catch (e) {
      debugPrint(
        'NitidoBackgroundService: Failed to stop background service: $e',
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
        'NitidoBackgroundService: Background service restart requested',
      );
    } catch (e) {
      debugPrint(
        'NitidoBackgroundService: Failed to restart background service: $e',
      );
    }
  }

  /// Whether the background service is currently running.
  Future<bool> isRunning() async {
    if (!_initialized) return false;
    return _service.isRunning();
  }
}

/// Retry helper: initializes UserSettingService with exponential backoff.
///
/// Catches any exception (including SqliteException 261 — database locked)
/// and retries up to [maxAttempts] times before giving up.
Future<void> _initSettingsWithRetry() async {
  const maxAttempts = 4;
  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      await UserSettingService.instance.initializeGlobalStateMap();
      return;
    } catch (e) {
      if (attempt < maxAttempts - 1) {
        await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      } else {
        debugPrint(
          'NitidoBackgroundService: settings init failed after $maxAttempts attempts: $e',
        );
      }
    }
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
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint(
    'NitidoBackgroundService: Background isolate started',
  );

  // Wait for the main isolate to finish its own DB init before touching SQLite.
  // Without this delay the two isolates race on the same DB file, causing
  // SqliteException 261 (database is locked) and a 2-3s cold-start freeze.
  await Future.delayed(const Duration(seconds: 4));

  // Initialize settings so the orchestrator can read toggle states.
  // Retry with exponential backoff in case the main isolate still holds the DB.
  await _initSettingsWithRetry();

  // Initialize local notifications for showing "pending" alerts
  final localNotif = LocalNotificationService.instance;
  try {
    await localNotif.initialize();
  } catch (e) {
    debugPrint(
      'NitidoBackgroundService: Failed to init local notifications in background: $e',
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
        'NitidoBackgroundService: Error showing pending notification: $e',
      );
    }
  };

  // Apply settings and start capturing — background-safe channels only.
  // NotificationCaptureSource uses a Flutter EventChannel that is bound to the
  // main FlutterEngine and must NOT be instantiated from a background isolate
  // (throws "This class should only be used in the main isolate"). SMS and
  // Binance API sources are safe here. The main isolate owns notifications.
  try {
    await orchestrator.applySettings(
      channels: {CaptureChannel.sms, CaptureChannel.api},
    );
    debugPrint(
      'NitidoBackgroundService: Orchestrator started in background isolate',
    );
  } catch (e) {
    debugPrint(
      'NitidoBackgroundService: Failed to start orchestrator in background: $e',
    );
  }

  // Listen for commands from the main isolate
  service.on('stop').listen((event) async {
    debugPrint(
      'NitidoBackgroundService: Received stop command',
    );
    await orchestrator.stop();
    await service.stopSelf();
  });

  service.on('restart').listen((event) async {
    debugPrint(
      'NitidoBackgroundService: Received restart command — reconfiguring orchestrator',
    );
    // Re-read settings (they may have changed in the main isolate's DB)
    try {
      await UserSettingService.instance.initializeGlobalStateMap();
      await orchestrator.applySettings(
        channels: {CaptureChannel.sms, CaptureChannel.api},
      );
    } catch (e) {
      debugPrint(
        'NitidoBackgroundService: Error restarting orchestrator: $e',
      );
    }
  });

  // If running as foreground service, update the notification
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();

    await service.setForegroundNotificationInfo(
      title: 'Nitido',
      content: 'Capturando movimientos bancarios',
    );
  }
}
