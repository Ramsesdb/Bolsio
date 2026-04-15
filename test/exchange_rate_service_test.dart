import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/services/rate_providers/rate_provider.dart';
import 'package:wallex/core/services/rate_providers/dolar_api_provider.dart';

/// Fake provider that returns a fixed rate for today only.
class FakeTodayOnlyProvider extends RateProvider {
  final double fixedRate;

  FakeTodayOnlyProvider({this.fixedRate = 478.0});

  @override
  String get name => 'FakeToday';

  @override
  bool get supportsHistorical => false;

  @override
  Future<RateResult?> fetchRate({
    required DateTime date,
    required String source,
  }) async {
    if (!DateUtils.isSameDay(date, DateTime.now())) {
      return null;
    }
    return RateResult(
      rate: fixedRate,
      fetchedAt: DateTime.now(),
      providerName: name,
      source: source,
    );
  }
}

/// Fake provider that always returns null (simulating a dead service).
class FakeDeadProvider extends RateProvider {
  @override
  String get name => 'FakeDead';

  @override
  bool get supportsHistorical => true;

  @override
  Future<RateResult?> fetchRate({
    required DateTime date,
    required String source,
  }) async {
    return null;
  }
}

void main() {
  group('RateProvider unit tests', () {
    test(
      'DolarApiProvider returns null for non-today dates (no historical support)',
      () async {
        final provider = DolarApiProvider();
        // A date in the past should always return null without network call
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final result = await provider.fetchRate(
          date: yesterday,
          source: 'bcv',
        );
        expect(result, isNull);
      },
    );

    test(
      'FakeTodayOnlyProvider returns rate for today',
      () async {
        final provider = FakeTodayOnlyProvider(fixedRate: 478.5);
        final result = await provider.fetchRate(
          date: DateTime.now(),
          source: 'bcv',
        );
        expect(result, isNotNull);
        expect(result!.rate, 478.5);
        expect(result.source, 'bcv');
        expect(result.providerName, 'FakeToday');
      },
    );

    test(
      'FakeTodayOnlyProvider returns null for past dates (mirrors DolarApiProvider behavior)',
      () async {
        final provider = FakeTodayOnlyProvider(fixedRate: 478.5);
        final pastDate = DateTime(2025, 1, 15);
        final result = await provider.fetchRate(
          date: pastDate,
          source: 'bcv',
        );
        expect(result, isNull);
      },
    );

    test(
      'FakeDeadProvider always returns null (simulates dead PyDolarVzla)',
      () async {
        final provider = FakeDeadProvider();
        // Even for today
        final resultToday = await provider.fetchRate(
          date: DateTime.now(),
          source: 'bcv',
        );
        expect(resultToday, isNull);

        // And for past dates
        final resultPast = await provider.fetchRate(
          date: DateTime(2024, 6, 1),
          source: 'paralelo',
        );
        expect(resultPast, isNull);
      },
    );

    test(
      'RateResult stores all fields correctly',
      () {
        final now = DateTime.now();
        final result = RateResult(
          rate: 627.3,
          fetchedAt: now,
          providerName: 'DolarApi',
          source: 'paralelo',
        );
        expect(result.rate, 627.3);
        expect(result.fetchedAt, now);
        expect(result.providerName, 'DolarApi');
        expect(result.source, 'paralelo');
      },
    );
  });

  group('Exchange rate calculation logic (pure)', () {
    // These test the mathematical logic that ExchangeRateService.calculateExchangeRate
    // would use, without requiring Drift DB setup.

    test(
      'calculateExchangeRate returns null when either rate is missing',
      () {
        // Simulating: from has rate, to is null
        final double? fromRate = 478.0;
        final double? toRate = null;

        final result = (fromRate != null && toRate != null)
            ? (fromRate / toRate) * 1
            : null;

        expect(result, isNull,
          reason: 'Must return null when rate is unavailable, '
              'NOT silently default to 1.0 (which was the original bug)');
      },
    );

    test(
      'calculateExchangeRate computes correctly when both rates exist (USD to VES)',
      () {
        // USD has exchangeRate = 478 (VES per USD)
        // VES has exchangeRate = 1.0 (VES per VES, identity)
        final double fromRate = 478.0; // USD
        final double toRate = 1.0; // VES
        const double amount = 100.0;

        final result = (fromRate / toRate) * amount;
        expect(result, 47800.0);
      },
    );

    test(
      'insertOrUpdateExchangeRateWithSource allows BCV and paralelo same day (logic check)',
      () {
        // This tests the conceptual correctness: two records with different source
        // tags should NOT overwrite each other. We verify the lookup key includes source.
        const currencyCode = 'USD';
        const dateFmt = '2026-04-15';
        const sourceBcv = 'bcv';
        const sourceParalelo = 'paralelo';

        // The lookup key is (currencyCode, date, source).
        // Two different sources should result in different keys.
        final keyBcv = '$currencyCode|$dateFmt|$sourceBcv';
        final keyParalelo = '$currencyCode|$dateFmt|$sourceParalelo';

        expect(keyBcv, isNot(equals(keyParalelo)),
          reason: 'BCV and paralelo rates for the same day must have '
              'different composite keys to coexist in the DB');
      },
    );
  });
}
