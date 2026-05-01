import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:nitido/core/models/auto_import/capture_channel.dart';
import 'package:nitido/core/models/auto_import/raw_capture_event.dart';
import 'package:nitido/core/services/auto_import/capture/capture_health_monitor.dart';

import 'capture_source.dart';

/// Notification-based capture source using the `notification_listener_service` plugin.
///
/// Only functional on Android. On iOS, [isAvailable] returns `false`
/// and [start] is a no-op.
///
/// Filters incoming notifications by [allowlistPackages] (e.g. `['com.bancodevenezuela.bdvdigital']`)
/// before emitting events. Notifications from unknown packages are silently discarded.
class NotificationCaptureSource implements CaptureSource {
  /// Android package names that are allowed through.
  final List<String> allowlistPackages;

  final StreamController<RawCaptureEvent> _controller =
      StreamController<RawCaptureEvent>.broadcast();

  StreamSubscription<ServiceNotificationEvent>? _subscription;

  NotificationCaptureSource({
    required this.allowlistPackages,
  });

  @override
  CaptureChannel get channel => CaptureChannel.notification;

  @override
  Stream<RawCaptureEvent> get events => _controller.stream;

  /// Whether there is currently a live subscription to the native stream.
  ///
  /// Used by [CaptureHealthMonitor] to diagnose zombie state — the OS may
  /// report the permission as granted while our Dart-side subscription is
  /// null or was cancelled after an error.
  bool get isSubscriptionAlive => _subscription != null;

  @override
  Future<bool> isAvailable() async {
    return Platform.isAndroid;
  }

  @override
  Future<bool> hasPermission() async {
    try {
      return await NotificationListenerService.isPermissionGranted();
    } catch (e) {
      debugPrint(
        'NotificationCaptureSource: Error checking notification listener permission: $e',
      );
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await NotificationListenerService.requestPermission();
    } catch (e) {
      debugPrint(
        'NotificationCaptureSource: Error requesting notification listener permission: $e',
      );
      return false;
    }
  }

  @override
  Future<void> start() async {
    await ensureSubscribed();
  }

  /// Make sure there is a live subscription to the native notification stream.
  ///
  /// - If [forceReconnect] is `false` and a subscription already exists, this
  ///   is a no-op. Safe to call on every health tick.
  /// - If [forceReconnect] is `true`, the current subscription (if any) is
  ///   cancelled first and a brand new one is created. Use this to recover
  ///   from a zombie state where MIUI revoked the native bind silently.
  Future<void> ensureSubscribed({bool forceReconnect = false}) async {
    if (!Platform.isAndroid) return;

    if (forceReconnect) {
      await _subscription?.cancel();
      _subscription = null;
    } else if (_subscription != null) {
      return;
    }

    debugPrint(
      'NotificationCaptureSource: subscribing to native stream '
      '(forceReconnect=$forceReconnect, packages=$allowlistPackages)',
    );

    _subscription = NotificationListenerService.notificationsStream.listen(
      _onNotification,
      onError: (error) {
        debugPrint(
          'NotificationCaptureSource: Error in notification stream: $error',
        );
        // Don't rethrow — keep the source usable. The next health tick will
        // notice and try to re-subscribe.
      },
      onDone: () {
        debugPrint(
          'NotificationCaptureSource: native stream closed — dropping subscription',
        );
        _subscription = null;
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onNotification(ServiceNotificationEvent event) {
    try {
      // Liveness signal to the health monitor — record BEFORE the allowlist
      // filter so that notifications from unrelated apps still prove the
      // stream is alive.
      try {
        CaptureHealthMonitor.instance.markEvent();
      } catch (e) {
        debugPrint('NotificationCaptureSource: health markEvent error: $e');
      }

      final packageName = event.packageName;

      debugPrint(
        'NotificationCaptureSource: raw event pkg=$packageName '
        'id=${event.id} hasRemoved=${event.hasRemoved} title="${event.title}"',
      );

      if (packageName == null) return;

      // Only allow notifications from known banking apps
      if (!allowlistPackages.contains(packageName)) return;

      // Compose rawText: title on first line, content on second line
      final title = event.title ?? '';
      final content = event.content ?? '';
      final rawText = '$title\n$content';

      // Plugin `notification_listener_service` 0.3.5 exposes `id` (int?) and
      // `hasRemoved` (bool?) but NOT `postTime`. Use `receivedAt` as proxy.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final nativeId = event.id?.toString();
      final wasRemoved = event.hasRemoved == true;

      _controller.add(RawCaptureEvent(
        rawText: rawText,
        sender: packageName,
        receivedAt: DateTime.now(),
        channel: CaptureChannel.notification,
        nativeNotifId: nativeId,
        nativeNotifPostTime: nowMs,
        hasRemoved: wasRemoved,
      ));
    } catch (e) {
      debugPrint(
        'NotificationCaptureSource: Error processing notification event: $e',
      );
      // Don't rethrow — keep the stream alive
    }
  }

  /// Clean up the stream controller and subscription.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
