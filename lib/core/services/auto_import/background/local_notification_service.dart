import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Channel IDs for local notifications used by the auto-import feature.
///
/// Two channels:
/// - [captureChannelId]: low-importance, used by the foreground service
///   notification (silent, persistent).
/// - [pendingChannelId]: default-importance, used for transient "X pending"
///   notifications with sound and badge.
class LocalNotificationService {
  static const String captureChannelId = 'wallex_capture';
  static const String captureChannelName = 'Captura de movimientos';
  static const String captureChannelDesc =
      'Notificacion persistente del servicio de captura';

  static const String pendingChannelId = 'wallex_pending';
  static const String pendingChannelName = 'Movimientos por revisar';
  static const String pendingChannelDesc =
      'Notificaciones cuando se capturan nuevos movimientos';

  /// Notification ID for the persistent foreground service notification.
  static const int foregroundNotificationId = 8880;

  /// Notification ID for the transient "pending imports" notification.
  static const int pendingNotificationId = 8881;

  static final LocalNotificationService instance =
      LocalNotificationService._();

  LocalNotificationService._();

  /// For testing: create an instance with a custom plugin.
  LocalNotificationService.forTesting({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _pluginOverride = plugin;

  FlutterLocalNotificationsPlugin? _pluginOverride;
  FlutterLocalNotificationsPlugin? _plugin;

  FlutterLocalNotificationsPlugin get plugin =>
      _pluginOverride ?? (_plugin ??= FlutterLocalNotificationsPlugin());

  bool _initialized = false;

  /// Callback invoked when the user taps on a notification.
  ///
  /// Set by the main app to navigate to PendingImportsPage.
  void Function(NotificationResponse)? onNotificationTap;

  /// Initialize the local notifications plugin and create Android channels.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize({
    void Function(NotificationResponse)? onTap,
  }) async {
    if (_initialized) return;
    if (kIsWeb) return;

    onNotificationTap = onTap;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    try {
      await plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );

      // Create notification channels (Android only)
      if (Platform.isAndroid) {
        final androidPlugin =
            plugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          // Low-importance channel for the foreground service
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              captureChannelId,
              captureChannelName,
              description: captureChannelDesc,
              importance: Importance.low,
              playSound: false,
              enableVibration: false,
              showBadge: false,
            ),
          );

          // Default-importance channel for pending import alerts
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              pendingChannelId,
              pendingChannelName,
              description: pendingChannelDesc,
              importance: Importance.defaultImportance,
              playSound: true,
              enableVibration: true,
              showBadge: true,
            ),
          );
        }
      }

      _initialized = true;
      developer.log(
        'LocalNotificationService initialized',
        name: 'LocalNotificationService',
      );
    } catch (e) {
      developer.log(
        'Failed to initialize LocalNotificationService: $e',
        name: 'LocalNotificationService',
      );
    }
  }

  /// Show (or update) a transient notification about pending imports.
  ///
  /// [count] is the number of unreviewed pending imports. If 0, the
  /// notification is cancelled.
  Future<void> showNewPendingNotification(int count) async {
    if (!_initialized) return;
    if (count <= 0) {
      await plugin.cancel(pendingNotificationId);
      return;
    }

    final body = formatPendingMessage(count);

    const androidDetails = AndroidNotificationDetails(
      pendingChannelId,
      pendingChannelName,
      channelDescription: pendingChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
      // Tapping opens the app — we handle navigation in the callback
    );

    await plugin.show(
      pendingNotificationId,
      'Wallex',
      body,
      const NotificationDetails(android: androidDetails),
      payload: 'pending_imports',
    );
  }

  /// Format the notification body for a given pending count.
  ///
  /// Exposed as a static method for testability.
  static String formatPendingMessage(int count) {
    if (count == 1) {
      return '1 movimiento por revisar';
    }
    return '$count movimientos por revisar';
  }

  void _handleNotificationResponse(NotificationResponse response) {
    if (response.payload == 'pending_imports') {
      onNotificationTap?.call(response);
    }
  }
}
