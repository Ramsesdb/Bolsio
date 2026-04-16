/// Capture channel from which a bank event was received.
enum CaptureChannel {
  sms,
  notification,
  api;

  /// Value stored in the database (matches CHECK constraint on `pending_imports.channel`).
  String get dbValue {
    switch (this) {
      case CaptureChannel.sms:
        return 'sms';
      case CaptureChannel.notification:
        return 'notification';
      case CaptureChannel.api:
        return 'api';
    }
  }

  /// Parse a database value back into a [CaptureChannel].
  static CaptureChannel fromDbValue(String value) {
    switch (value) {
      case 'sms':
        return CaptureChannel.sms;
      case 'notification':
        return CaptureChannel.notification;
      case 'api':
        return CaptureChannel.api;
      default:
        throw ArgumentError('Unknown CaptureChannel dbValue: $value');
    }
  }
}
