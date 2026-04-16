import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/services/auto_import/background/local_notification_service.dart';
import 'package:wallex/core/services/auto_import/background/wallex_background_service.dart';

void main() {
  group('WallexBackgroundService', () {
    test('instance is a singleton', () {
      final a = WallexBackgroundService.instance;
      final b = WallexBackgroundService.instance;
      expect(identical(a, b), isTrue);
    });

    test('forTesting constructor does not throw', () {
      final service = WallexBackgroundService.forTesting();
      expect(service, isNotNull);
    });

    test('notification channel IDs are correct', () {
      expect(
        LocalNotificationService.captureChannelId,
        equals('wallex_capture'),
      );
      expect(
        LocalNotificationService.pendingChannelId,
        equals('wallex_pending'),
      );
    });

    test('foreground notification ID is stable', () {
      expect(
        LocalNotificationService.foregroundNotificationId,
        equals(8880),
      );
    });

    test('pending notification ID is stable', () {
      expect(
        LocalNotificationService.pendingNotificationId,
        equals(8881),
      );
    });

    test('notification channel names are non-empty', () {
      expect(
        LocalNotificationService.captureChannelName.isNotEmpty,
        isTrue,
      );
      expect(
        LocalNotificationService.pendingChannelName.isNotEmpty,
        isTrue,
      );
    });
  });
}
