import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/services/auto_import/binance/binance_credentials_store.dart';

void main() {
  late BinanceCredentialsStore store;

  setUp(() {
    // Initialize mock storage with empty values so tests don't need the plugin.
    FlutterSecureStorage.setMockInitialValues({});
    store = BinanceCredentialsStore.forTesting(const FlutterSecureStorage());
  });

  group('BinanceCredentialsStore', () {
    test('save then load returns same values', () async {
      await store.save(
        apiKey: 'fake_api_key_for_tests',
        apiSecret: 'fake_secret_for_tests',
      );

      final creds = await store.load();

      expect(creds, isNotNull);
      expect(creds!.apiKey, 'fake_api_key_for_tests');
      expect(creds.apiSecret, 'fake_secret_for_tests');
    });

    test('load returns null when nothing is stored', () async {
      final creds = await store.load();
      expect(creds, isNull);
    });

    test('hasCredentials returns true when both key and secret are present',
        () async {
      await store.save(
        apiKey: 'fake_api_key_for_tests',
        apiSecret: 'fake_secret_for_tests',
      );

      expect(await store.hasCredentials(), isTrue);
    });

    test('hasCredentials returns false when storage is empty', () async {
      expect(await store.hasCredentials(), isFalse);
    });

    test('clear removes all credentials', () async {
      await store.save(
        apiKey: 'fake_api_key_for_tests',
        apiSecret: 'fake_secret_for_tests',
      );

      await store.clear();

      final creds = await store.load();
      expect(creds, isNull);
      expect(await store.hasCredentials(), isFalse);
    });

    test('save overwrites previous credentials', () async {
      await store.save(
        apiKey: 'fake_old_key',
        apiSecret: 'fake_old_secret',
      );

      await store.save(
        apiKey: 'fake_new_key',
        apiSecret: 'fake_new_secret',
      );

      final creds = await store.load();
      expect(creds, isNotNull);
      expect(creds!.apiKey, 'fake_new_key');
      expect(creds.apiSecret, 'fake_new_secret');
    });
  });
}
