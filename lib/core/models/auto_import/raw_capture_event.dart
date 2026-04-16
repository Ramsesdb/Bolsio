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

  const RawCaptureEvent({
    required this.rawText,
    required this.sender,
    required this.receivedAt,
    required this.channel,
  });

  @override
  String toString() {
    return 'RawCaptureEvent('
        'channel: ${channel.dbValue}, '
        'sender: $sender, '
        'receivedAt: $receivedAt, '
        'rawText: "${rawText.length > 80 ? '${rawText.substring(0, 80)}...' : rawText}"'
        ')';
  }
}
