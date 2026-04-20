import 'package:flutter/foundation.dart';

import 'capture_channel.dart';

/// Immutable representation of a raw event captured from SMS or a push notification.
///
/// This is the input to the bank profile parsers before any interpretation has been done.
@immutable
class RawCaptureEvent {
  /// The full raw text content of the SMS body or notification body.
  final String rawText;

  /// The sender identifier: SMS short-code/number, or the notification package name.
  final String sender;

  /// Timestamp when the event was received on the device.
  final DateTime receivedAt;

  /// Which channel delivered this event.
  final CaptureChannel channel;

  // -----------------------------------------------------------------
  // Tanda 4 — dedupe-robusto metadata (notification channel only).
  // -----------------------------------------------------------------

  /// Native Android notification id, string-ified (plugin exposes it as `int?`).
  ///
  /// When Android reposts the SAME logical notification (e.g. BDV updates the
  /// line with a later balance, or the user taps it on some OEMs), the `id`
  /// usually stays the same. When it differs, we fall back to the content hash.
  /// Null on SMS and when the plugin doesn't expose it.
  final String? nativeNotifId;

  /// Timestamp (epoch ms) when the native OS posted the notification.
  ///
  /// The `notification_listener_service` plugin versions <= 0.3.5 do NOT
  /// expose this field directly, so sources fall back to the Dart-side
  /// `receivedAt` timestamp as a proxy. Left `null` when unknown.
  final int? nativeNotifPostTime;

  /// `true` when the native event signalled that the notification was REMOVED
  /// from the tray (plugin field `ServiceNotificationEvent.hasRemoved`).
  ///
  /// Such events must NOT be processed as new captures; the orchestrator only
  /// uses them to mark the fingerprint as "user-removed" in the registry.
  final bool hasRemoved;

  const RawCaptureEvent({
    required this.rawText,
    required this.sender,
    required this.receivedAt,
    required this.channel,
    this.nativeNotifId,
    this.nativeNotifPostTime,
    this.hasRemoved = false,
  });

  @override
  String toString() {
    return 'RawCaptureEvent('
        'channel: ${channel.dbValue}, '
        'sender: $sender, '
        'receivedAt: $receivedAt, '
        'nativeNotifId: $nativeNotifId, '
        'hasRemoved: $hasRemoved, '
        'rawText: "${rawText.length > 80 ? '${rawText.substring(0, 80)}...' : rawText}"'
        ')';
  }
}
