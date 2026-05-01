import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:nitido/core/services/rate_providers/frankfurter_provider.dart';
import 'package:nitido/core/services/rate_providers/rate_source.dart';

/// Unit tests for [FrankfurterRateProvider].
///
/// Covers the four contract guarantees per design §4 / spec scenarios:
///
///   1. success path returns the rate tagged `auto_frankfurter`;
///   2. HTTP 4xx (e.g. unsupported currency) returns null;
///   3. network failure (timeout / socket error) returns null;
///   4. malformed JSON / missing `rates[to]` returns null.
///
/// All HTTP traffic is mocked via `package:http/testing.dart` — no real
/// network call leaves the test process. This mirrors the existing
/// pattern in `test/auto_import/binance_api_capture_source_test.dart`.
void main() {
  group('FrankfurterRateProvider.fetchPair', () {
    test('returns rate on 200 success with valid body', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.url.host, 'api.frankfurter.app');
        expect(request.url.queryParameters['from'], 'EUR');
        expect(request.url.queryParameters['to'], 'GBP');
        return http.Response(
          jsonEncode({
            'amount': 1.0,
            'base': 'EUR',
            'date': '2026-04-29',
            'rates': {'GBP': 0.846},
          }),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchPair(from: 'EUR', to: 'GBP');

      expect(result, isNotNull);
      expect(result!.rate, 0.846);
      expect(result.source, RateSource.autoFrankfurter.dbValue);
      expect(result.providerName, 'Frankfurter');
    });

    test('returns 1.0 sentinel for identity pair without network call',
        () async {
      bool called = false;
      final mockClient = http_testing.MockClient((request) async {
        called = true;
        return http.Response('', 500);
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchPair(from: 'USD', to: 'USD');

      expect(called, isFalse, reason: 'identity must skip the network');
      expect(result, isNotNull);
      expect(result!.rate, 1.0);
    });

    test('returns null on HTTP 404 (unsupported currency)', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response('{"message":"not found"}', 404);
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchPair(from: 'USD', to: 'XAU');

      expect(result, isNull);
    });

    test('returns null when network call throws', () async {
      final mockClient = http_testing.MockClient((request) async {
        throw http.ClientException('connection reset by peer');
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchPair(from: 'USD', to: 'EUR');

      expect(result, isNull);
    });

    test('returns null on malformed JSON', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response('not json at all', 200);
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchPair(from: 'USD', to: 'EUR');

      expect(result, isNull);
    });

    test('returns null when rates map missing target key', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({
            'amount': 1.0,
            'base': 'USD',
            'date': '2026-04-29',
            'rates': {'GBP': 0.79}, // EUR not present
          }),
          200,
        );
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchPair(from: 'USD', to: 'EUR');

      expect(result, isNull);
    });

    test('returns null when rate is non-positive', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({
            'rates': {'EUR': 0},
          }),
          200,
        );
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchPair(from: 'USD', to: 'EUR');

      expect(result, isNull);
    });
  });

  group('FrankfurterRateProvider.supportsPair', () {
    test('USD↔EUR is supported', () {
      expect(FrankfurterRateProvider.supportsPair('USD', 'EUR'), isTrue);
    });

    test('VES is unsupported (LATAM, not in Frankfurter)', () {
      expect(FrankfurterRateProvider.supportsPair('USD', 'VES'), isFalse);
      expect(FrankfurterRateProvider.supportsPair('VES', 'EUR'), isFalse);
    });

    test('crypto codes are unsupported', () {
      expect(FrankfurterRateProvider.supportsPair('USD', 'BTC'), isFalse);
      expect(FrankfurterRateProvider.supportsPair('ETH', 'EUR'), isFalse);
      expect(FrankfurterRateProvider.supportsPair('USDT', 'USD'), isFalse);
    });

    test('case-insensitive', () {
      expect(FrankfurterRateProvider.supportsPair('usd', 'eur'), isTrue);
      expect(FrankfurterRateProvider.supportsPair('btc', 'usd'), isFalse);
    });

    test('identity is supported (trivial)', () {
      expect(FrankfurterRateProvider.supportsPair('JPY', 'JPY'), isTrue);
    });
  });

  group('FrankfurterRateProvider.fetchRate (RateProvider interface)', () {
    test('returns null when source is not auto_frankfurter', () async {
      final mockClient = http_testing.MockClient((request) async {
        fail('must not hit the network when source mismatches');
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchRate(
        date: DateTime.now(),
        source: 'bcv',
      );

      expect(result, isNull);
    });

    test('returns null for non-today dates (no historical support)',
        () async {
      final mockClient = http_testing.MockClient((request) async {
        fail('must not hit the network for past dates');
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchRate(
        date: DateTime.now().subtract(const Duration(days: 3)),
        source: RateSource.autoFrankfurter.dbValue,
      );

      expect(result, isNull);
    });

    test('skips network for known-unsupported source currency', () async {
      bool called = false;
      final mockClient = http_testing.MockClient((request) async {
        called = true;
        return http.Response('', 500);
      });

      final provider = FrankfurterRateProvider(httpClient: mockClient);
      final result = await provider.fetchRate(
        date: DateTime.now(),
        source: RateSource.autoFrankfurter.dbValue,
        currencyCode: 'BTC',
      );

      expect(called, isFalse);
      expect(result, isNull);
    });
  });
}
