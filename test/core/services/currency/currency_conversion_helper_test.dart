import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/services/currency/currency_conversion_helper.dart';
import 'package:wallex/core/services/rate_providers/rate_source.dart';

/// Phase 9 unit suite for [CurrencyConversionHelper.convertMixedCurrenciesToTarget].
///
/// Drift-free — we inject a fake [RateLookupFn] via
/// [CurrencyConversionHelper.forTesting] so we exercise the conversion +
/// missing-rate aggregation logic without booting a database.
///
/// Decision: when a per-currency rate stream emits `null`, the
/// contribution is EXCLUDED from the total and the currency code is
/// added to `missingRateCurrencies`. This matches the design.md §4
/// resolved decision #6 (no silent `?? 1.0` fallback) and gives the UI
/// the data it needs to surface "tasa no configurada" hints.
void main() {
  group('CurrencyConversionHelper.convertMixedCurrenciesToTarget', () {
    /// Builds a fake `RateLookupFn` from a static rate table.
    /// Returns `null` for any pair not in the table — simulating "tasa
    /// no configurada".
    RateLookupFn rateTable(Map<({String from, String to}), double> table) {
      return ({
        required String fromCurrency,
        required String toCurrency,
        num amount = 1,
        DateTime? date,
        String? source,
      }) {
        final key = (from: fromCurrency, to: toCurrency);
        final rate = table[key];
        if (rate == null) {
          return Stream<double?>.value(null);
        }
        return Stream<double?>.value(rate * amount.toDouble());
      };
    }

    test('empty map emits 0.0 with empty missing set', () async {
      final helper = CurrencyConversionHelper.forTesting(
        rateLookup: rateTable({}),
      );

      final result = await helper
          .convertMixedCurrenciesToTarget(
            byNative: Stream.value(<String, double>{}),
            target: 'USD',
          )
          .first;

      expect(result.convertedTotal, 0.0);
      expect(result.missingRateCurrencies, isEmpty);
      expect(result.hasMissingRates, isFalse);
    });

    test(
      'all amounts in target currency — sum unchanged, no rate calls',
      () async {
        var rateLookupCalls = 0;
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: ({
            required String fromCurrency,
            required String toCurrency,
            num amount = 1,
            DateTime? date,
            String? source,
          }) {
            rateLookupCalls += 1;
            return Stream<double?>.value(null);
          },
        );

        final result = await helper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({'USD': 100.0}),
              target: 'USD',
            )
            .first;

        expect(result.convertedTotal, 100.0);
        expect(result.missingRateCurrencies, isEmpty);
        expect(
          rateLookupCalls,
          0,
          reason:
              'Identity contribution must short-circuit; no rate lookup '
              'should fire when native == target.',
        );
      },
    );

    test(
      'mix of two currencies — converts non-target portion correctly',
      () async {
        // USD account 100 USD + VES account 4000 VES, target USD,
        // 1 VES = 0.025 USD (i.e. 1 USD = 40 VES at BCV)
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: rateTable({
            (from: 'VES', to: 'USD'): 0.025,
          }),
        );

        final result = await helper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({'USD': 100.0, 'VES': 4000.0}),
              target: 'USD',
            )
            .first;

        expect(result.convertedTotal, 200.0); // 100 + 4000*0.025
        expect(result.missingRateCurrencies, isEmpty);
      },
    );

    test(
      'one currency missing rate — excludes it and reports in missing set',
      () async {
        // EUR has a rate, JPY does NOT — target USD.
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: rateTable({
            (from: 'EUR', to: 'USD'): 1.10,
            // (JPY, USD) intentionally absent → null
          }),
        );

        final result = await helper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({
                'USD': 50.0,
                'EUR': 100.0,
                'JPY': 1000.0,
              }),
              target: 'USD',
            )
            .first;

        // 50 native + 100*1.10 EUR portion = 160.0 (JPY excluded)
        expect(result.convertedTotal, 160.0);
        expect(result.missingRateCurrencies, {'JPY'});
        expect(result.hasMissingRates, isTrue);
      },
    );

    test(
      'multiple currencies missing rate — all reported, total partial',
      () async {
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: rateTable({
            // No rates at all
          }),
        );

        final result = await helper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({
                'EUR': 100.0,
                'JPY': 1000.0,
                'USD': 50.0, // identity, kept
              }),
              target: 'USD',
            )
            .first;

        expect(result.convertedTotal, 50.0);
        expect(result.missingRateCurrencies, {'EUR', 'JPY'});
      },
    );

    test('case-insensitive target match — vesB vs VES', () async {
      // Target lowercased should still hit the identity branch.
      final helper = CurrencyConversionHelper.forTesting(
        rateLookup: rateTable({}),
      );

      final result = await helper
          .convertMixedCurrenciesToTarget(
            byNative: Stream.value({'ves': 1000.0, 'VES': 500.0}),
            target: 'ves',
          )
          .first;

      // Both entries should be treated as identity (target after upper)
      expect(result.convertedTotal, 1500.0);
      expect(result.missingRateCurrencies, isEmpty);
    });

    test(
      'forwards RateSource.dbValue to the lookup as `source`',
      () async {
        String? capturedSource;
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: ({
            required String fromCurrency,
            required String toCurrency,
            num amount = 1,
            DateTime? date,
            String? source,
          }) {
            capturedSource = source;
            return Stream<double?>.value(0.025 * amount.toDouble());
          },
        );

        await helper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({'VES': 4000.0}),
              target: 'USD',
              source: RateSource.paralelo,
            )
            .first;

        expect(capturedSource, 'paralelo');
      },
    );

    test(
      'forwards RateSource.bcv as the dbValue',
      () async {
        String? capturedSource;
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: ({
            required String fromCurrency,
            required String toCurrency,
            num amount = 1,
            DateTime? date,
            String? source,
          }) {
            capturedSource = source;
            return Stream<double?>.value(0.025 * amount.toDouble());
          },
        );

        await helper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({'VES': 4000.0}),
              target: 'USD',
              source: RateSource.bcv,
            )
            .first;

        expect(capturedSource, 'bcv');
      },
    );

    test('null source forwarded as null', () async {
      String? capturedSource = '<not-set>';
      final helper = CurrencyConversionHelper.forTesting(
        rateLookup: ({
          required String fromCurrency,
          required String toCurrency,
          num amount = 1,
          DateTime? date,
          String? source,
        }) {
          capturedSource = source;
          return Stream<double?>.value(0.025 * amount.toDouble());
        },
      );

      await helper
          .convertMixedCurrenciesToTarget(
            byNative: Stream.value({'VES': 4000.0}),
            target: 'USD',
            source: null,
          )
          .first;

      expect(capturedSource, isNull);
    });

    test(
      'spec scenario — toggle BCV→Paralelo only changes non-USD '
      'portion (USD account stays at 100)',
      () async {
        // From transactions/spec.md scenario "Toggle BCV→Paralelo NO
        // altera porción nativa USD": dual(USD, VES), USD account 100,
        // VES account 1000, BCV=40 (1 VES = 0.025 USD), Paralelo=45
        // (1 VES ≈ 0.02222 USD). Expected total under BCV: 125 USD; under
        // Paralelo: ~122.22. Native USD 100 must NOT change.
        final bcvHelper = CurrencyConversionHelper.forTesting(
          rateLookup: rateTable({
            (from: 'VES', to: 'USD'): 1 / 40,
          }),
        );
        final paraleloHelper = CurrencyConversionHelper.forTesting(
          rateLookup: rateTable({
            (from: 'VES', to: 'USD'): 1 / 45,
          }),
        );

        final bcvResult = await bcvHelper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({'USD': 100.0, 'VES': 1000.0}),
              target: 'USD',
            )
            .first;
        final paraleloResult = await paraleloHelper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({'USD': 100.0, 'VES': 1000.0}),
              target: 'USD',
            )
            .first;

        expect(bcvResult.convertedTotal, closeTo(125.0, 1e-9));
        expect(
          paraleloResult.convertedTotal,
          closeTo(100.0 + 1000.0 / 45.0, 1e-9),
        );
      },
    );

    test(
      'spec scenario — single(VES) with USD + VES accounts, USD '
      'portion converted, VES portion native',
      () async {
        // From transactions/spec.md "Modo single_bs con cuentas USD":
        // USD account 50, VES account 500, BCV=40 → total 2500 VES.
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: rateTable({
            (from: 'USD', to: 'VES'): 40.0,
          }),
        );

        final result = await helper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({'USD': 50.0, 'VES': 500.0}),
              target: 'VES',
            )
            .first;

        expect(result.convertedTotal, 2500.0);
        expect(result.missingRateCurrencies, isEmpty);
      },
    );

    test(
      'spec scenario — single(EUR) with JPY missing rate — JPY '
      'group excluded, missing reported',
      () async {
        // From transactions/spec.md "Tasa faltante para un grupo":
        // single(EUR), JPY account 1000 with no rate → JPY excluded,
        // EUR portion preserved.
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: rateTable({
            // No JPY→EUR rate
          }),
        );

        final result = await helper
            .convertMixedCurrenciesToTarget(
              byNative: Stream.value({'EUR': 200.0, 'JPY': 1000.0}),
              target: 'EUR',
            )
            .first;

        expect(result.convertedTotal, 200.0); // EUR identity only
        expect(result.missingRateCurrencies, {'JPY'});
      },
    );
  });

  group('CurrencyConversionHelper.convertMixedCurrenciesToTotal', () {
    test('drops the missing-set side-channel', () async {
      RateLookupFn rateTable(Map<({String from, String to}), double> table) {
        return ({
          required String fromCurrency,
          required String toCurrency,
          num amount = 1,
          DateTime? date,
          String? source,
        }) {
          final key = (from: fromCurrency, to: toCurrency);
          final rate = table[key];
          if (rate == null) return Stream<double?>.value(null);
          return Stream<double?>.value(rate * amount.toDouble());
        };
      }

      final helper = CurrencyConversionHelper.forTesting(
        rateLookup: rateTable({
          (from: 'EUR', to: 'USD'): 1.10,
        }),
      );

      final total = await helper
          .convertMixedCurrenciesToTotal(
            byNative: Stream.value({
              'USD': 50.0,
              'EUR': 100.0,
              'JPY': 1000.0, // missing rate, excluded
            }),
            target: 'USD',
          )
          .first;

      expect(total, 160.0); // 50 + 100*1.10, JPY dropped silently
    });
  });

  group('MixedCurrencyConversionResult value object', () {
    test('equality with same total + missing set (order-independent)', () {
      final a = MixedCurrencyConversionResult(
        convertedTotal: 100.0,
        missingRateCurrencies: {'JPY', 'EUR'},
      );
      final b = MixedCurrencyConversionResult(
        convertedTotal: 100.0,
        missingRateCurrencies: {'EUR', 'JPY'},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality with different total', () {
      final a = MixedCurrencyConversionResult(
        convertedTotal: 100.0,
        missingRateCurrencies: const {},
      );
      final b = MixedCurrencyConversionResult(
        convertedTotal: 100.5,
        missingRateCurrencies: const {},
      );
      expect(a, isNot(b));
    });

    test('inequality with different missing set', () {
      final a = MixedCurrencyConversionResult(
        convertedTotal: 100.0,
        missingRateCurrencies: {'JPY'},
      );
      final b = MixedCurrencyConversionResult(
        convertedTotal: 100.0,
        missingRateCurrencies: {'EUR'},
      );
      expect(a, isNot(b));
    });

    test('toString includes total and missing', () {
      final r = MixedCurrencyConversionResult(
        convertedTotal: 42.5,
        missingRateCurrencies: {'JPY'},
      );
      expect(r.toString(), contains('42.5'));
      expect(r.toString(), contains('JPY'));
    });
  });
}
