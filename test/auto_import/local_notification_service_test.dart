import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/services/auto_import/background/local_notification_service.dart';

void main() {
  group('LocalNotificationService', () {
    test('instance is a singleton', () {
      final a = LocalNotificationService.instance;
      final b = LocalNotificationService.instance;
      expect(identical(a, b), isTrue);
    });

    test('forTesting constructor does not throw', () {
      final service = LocalNotificationService.forTesting();
      expect(service, isNotNull);
    });

    test('formatPendingMessage for count=1 uses singular', () {
      final message = LocalNotificationService.formatPendingMessage(1);
      expect(message, equals('1 movimiento por revisar'));
    });

    test('formatPendingMessage for count=5 uses plural', () {
      final message = LocalNotificationService.formatPendingMessage(5);
      expect(message, equals('5 movimientos por revisar'));
    });

    test('formatPendingMessage for count=0 uses plural', () {
      final message = LocalNotificationService.formatPendingMessage(0);
      expect(message, equals('0 movimientos por revisar'));
    });

    test('formatPendingMessage for count=100 uses plural', () {
      final message = LocalNotificationService.formatPendingMessage(100);
      expect(message, equals('100 movimientos por revisar'));
    });

    test('channel IDs match expected values', () {
      expect(
        LocalNotificationService.captureChannelId,
        equals('wallex_capture'),
      );
      expect(
        LocalNotificationService.pendingChannelId,
        equals('wallex_pending'),
      );
    });

    test('channel descriptions are non-empty', () {
      expect(
        LocalNotificationService.captureChannelDesc.isNotEmpty,
        isTrue,
      );
      expect(
        LocalNotificationService.pendingChannelDesc.isNotEmpty,
        isTrue,
      );
    });

    test('notification IDs are distinct', () {
      expect(
        LocalNotificationService.foregroundNotificationId,
        isNot(equals(LocalNotificationService.pendingNotificationId)),
      );
    });
  });
}
