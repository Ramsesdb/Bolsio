import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/raw_capture_event.dart';

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
    if (!Platform.isAndroid) return;
    if (_subscription != null) return; // Already listening

    debugPrint('NotificationCaptureSource: started listening for packages: $allowlistPackages');

    _subscription =
        NotificationListenerService.notificationsStream.listen(
      _onNotification,
      onError: (error) {
        debugPrint(
          'NotificationCaptureSource: Error in notification stream: $error',
        );
        // Don't rethrow — keep the stream alive
      },
    );
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onNotification(ServiceNotificationEvent event) {
    try {
      final packageName = event.packageName;

      if (packageName == null) return;

      // Only allow notifications from known banking apps
      if (!allowlistPackages.contains(packageName)) return;

      // Compose rawText: title on first line, content on second line
      final title = event.title ?? '';
      final content = event.content ?? '';
      final rawText = '$title\n$content';

      _controller.add(RawCaptureEvent(
        rawText: rawText,
        sender: packageName,
        receivedAt: DateTime.now(),
        channel: CaptureChannel.notification,
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
