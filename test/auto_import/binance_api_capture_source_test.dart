import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nitido/core/models/auto_import/capture_channel.dart';
import 'package:nitido/core/services/auto_import/binance/binance_api_client.dart';
import 'package:nitido/core/services/auto_import/binance/binance_credentials_store.dart';
import 'package:nitido/core/services/auto_import/capture/binance_api_capture_source.dart';

void main() {
  late BinanceCredentialsStore credentialsStore;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    credentialsStore =
        BinanceCredentialsStore.forTesting(const FlutterSecureStorage());
  });

  group('BinanceApiCaptureSource', () {
    test('channel is api', () {
      final source = BinanceApiCaptureSource(
        credentialsStore: credentialsStore,
      );
      expect(source.channel, CaptureChannel.api);
    });

    test('isAvailable always returns true', () async {
      final source = BinanceApiCaptureSource(
        credentialsStore: credentialsStore,
      );
      expect(await source.isAvailable(), isTrue);
    });

    test('hasPermission returns false without credentials', () async {
      final source = BinanceApiCaptureSource(
        credentialsStore: credentialsStore,
      );
      expect(await source.hasPermission(), isFalse);
    });

    test('hasPermission returns true with credentials', () async {
      await credentialsStore.save(
        apiKey: 'fake_api_key_for_tests',
        apiSecret: 'fake_secret_for_tests',
      );

      final source = BinanceApiCaptureSource(
        credentialsStore: credentialsStore,
      );
      expect(await source.hasPermission(), isTrue);
    });

    test('start without credentials does not poll (no events emitted)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final source = BinanceApiCaptureSource(
        credentialsStore: credentialsStore,
        prefsOverride: prefs,
      );

      final events = <dynamic>[];
      source.events.listen(events.add);

      await source.start();

      // Give any async operations time to complete
      await Future.delayed(const Duration(milliseconds: 100));

      expect(events, isEmpty);

      await source.stop();
    });

    test('poll with credentials and mock data emits events', () async {
      await credentialsStore.save(
        apiKey: 'fake_api_key_for_tests',
        apiSecret: 'fake_secret_for_tests',
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Mock HTTP client that returns data for /api/v3/time and c2c endpoint
      final mockClient = http_testing.MockClient((request) async {
        final path = request.url.path;

        if (path == '/api/v3/time') {
          return http.Response(
            jsonEncode({
              'serverTime': DateTime.now().millisecondsSinceEpoch,
            }),
            200,
          );
        }

        if (path.contains('c2c/orderMatch')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'orderNumber': 'MOCK_ORDER_001',
                  'tradeType': 'BUY',
                  'asset': 'USDT',
                  'fiat': 'VES',
                  'amount': '100.00',
                  'totalPrice': '3750000.00',
                  'unitPrice': '37500.00',
                  'counterPartNickName': 'MockUser',
                  'createTime': DateTime.now().millisecondsSinceEpoch,
                  'orderStatus': 'COMPLETED',
                },
              ],
            }),
            200,
          );
        }

        // All other endpoints return empty data
        if (path.contains('fiat/orders') ||
            path.contains('fiat/payments') ||
            path.contains('pay/transactions')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }

        if (path.contains('capital/deposit') ||
            path.contains('capital/withdraw')) {
          return http.Response(jsonEncode([]), 200);
        }

        return http.Response('Not found', 404);
      });

      final client = BinanceApiClient(
        credentialsStore: credentialsStore,
        httpClient: mockClient,
        baseUrl: 'https://mock.binance.test',
      );

      final source = BinanceApiCaptureSource(
        client: client,
        credentialsStore: credentialsStore,
        prefsOverride: prefs,
        pollInterval: const Duration(hours: 1), // Won't fire in test
      );

      final events = <dynamic>[];
      source.events.listen(events.add);

      // syncServerTime + poll
      await client.syncServerTime();
      await source.poll();

      // Should have at least one event from the C2C endpoint
      expect(events, isNotEmpty);
      expect(events.first.sender, 'binance:c2c_p2p');
      expect(events.first.channel, CaptureChannel.api);

      // Verify the cursor was persisted
      final cursor = prefs.getInt('binance_lastsync_c2c');
      expect(cursor, isNotNull);
      expect(cursor! > 0, isTrue);

      await source.stop();
      mockClient.close();
    });

    test('poll updates cursors correctly across multiple calls', () async {
      await credentialsStore.save(
        apiKey: 'fake_api_key_for_tests',
        apiSecret: 'fake_secret_for_tests',
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      int callCount = 0;
      final mockClient = http_testing.MockClient((request) async {
        final path = request.url.path;

        if (path == '/api/v3/time') {
          return http.Response(
            jsonEncode({
              'serverTime': DateTime.now().millisecondsSinceEpoch,
            }),
            200,
          );
        }

        if (path.contains('c2c/orderMatch')) {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'orderNumber': 'ORDER_1',
                    'tradeType': 'BUY',
                    'asset': 'USDT',
                    'amount': '50.00',
                    'createTime': 1712000000000,
                    'orderStatus': 'COMPLETED',
                  },
                ],
              }),
              200,
            );
          } else {
            // Second poll: no new data
            return http.Response(jsonEncode({'data': []}), 200);
          }
        }

        if (path.contains('fiat/orders') ||
            path.contains('fiat/payments') ||
            path.contains('pay/transactions')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }

        if (path.contains('capital/deposit') ||
            path.contains('capital/withdraw')) {
          return http.Response(jsonEncode([]), 200);
        }

        return http.Response('Not found', 404);
      });

      final client = BinanceApiClient(
        credentialsStore: credentialsStore,
        httpClient: mockClient,
        baseUrl: 'https://mock.binance.test',
      );

      final source = BinanceApiCaptureSource(
        client: client,
        credentialsStore: credentialsStore,
        prefsOverride: prefs,
      );

      final events = <dynamic>[];
      source.events.listen(events.add);

      await client.syncServerTime();

      // First poll
      await source.poll();
      expect(events.length, 1);

      final cursorAfterFirst = prefs.getInt('binance_lastsync_c2c');
      expect(cursorAfterFirst, 1712000000000);

      // Second poll (no new data)
      await source.poll();
      expect(events.length, 1); // No new events

      await source.stop();
      mockClient.close();
    });
  });
}
