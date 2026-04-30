import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/models/currency/currency_display_policy.dart';
import 'package:wallex/core/services/currency/currency_conversion_helper.dart';
import 'package:wallex/core/services/rate_providers/rate_provider_chain.dart';
import 'package:wallex/core/services/rate_providers/rate_source.dart';

/// Phase 10 task 10.7 — Dashboard mixed-currency totals integration.
///
/// THE critical test of the absorbed bug: under `DualMode(USD, VES)` with
/// both a USD-native and a VES-native account, toggling the rate source
/// (BCV ↔ Paralelo) MUST leave the native portions FIXED. Only the
/// converted-from-foreign portion changes.
///
/// This is end-to-end at the Dart layer — we exercise `CurrencyDisplayPolicy`
/// + `RateProviderChain.sourceForPair` + `CurrencyConversionHelper.convertMixedCurrenciesToTarget`
/// together, simulating the same chain `IncomeOrExpenseCard` and
/// `TotalBalanceSummaryWidget` use post-Phase 6. We do NOT boot the full
/// dashboard widget tree — that would require AppDB, path_provider, and
/// asset bundle stubbing that this codebase does not currently expose. The
/// test asserts the LOAD-BEARING invariant (native portion stability) at
/// the helper layer where the Phase 9 fix actually lives.
///
/// Companion coverage:
///   - `currency_conversion_helper_test.dart` (Phase 9, 17 tests) covers
///     the same invariant via the `MixedCurrencyConversionResult` shape;
///     this file frames it as the dashboard scenario users see.
///   - `income_or_expense_card_test.dart` (Phase 6, 13 tests) pins the
///     widget contract above the helper.
void main() {
  /// Builds a fake `RateLookupFn` that simulates the dashboard's
  /// `ExchangeRateService.calculateExchangeRate` return for VES↔USD pairs
  /// at the given rate (1 USD = `vesPerUsd` VES). Returns `null` for any
  /// unsupported pair to simulate "tasa no configurada".
  RateLookupFn vesUsdRateTable({required double vesPerUsd}) {
    return ({
      required String fromCurrency,
      required String toCurrency,
      num amount = 1,
      DateTime? date,
      String? source,
    }) {
      // Only VES → USD is supported; everything else returns null.
      if (fromCurrency == 'VES' && toCurrency == 'USD') {
        return Stream<double?>.value(amount.toDouble() / vesPerUsd);
      }
      if (fromCurrency == 'USD' && toCurrency == 'VES') {
        return Stream<double?>.value(amount.toDouble() * vesPerUsd);
      }
      return Stream<double?>.value(null);
    };
  }

  group(
    'Dashboard mixed-currency totals — DualMode(USD, VES) BCV↔Paralelo '
    'toggle (Task 10.7)',
    () {
      const policy = DualMode(primary: 'USD', secondary: 'VES');

      // Per orchestrator brief 10.4 / tasks.md 10.7: account in USD with
      // 100, account in VES with 1000, BCV=40, Paralelo=45. Expected
      // primary line: 100 + 1000/40 = 125 USD (BCV); 100 + 1000/45 ≈
      // 122.22 USD (Paralelo). NATIVE USD portion of 100 is INVARIANT.
      const usdNativeBalance = 100.0;
      const vesNativeBalance = 1000.0;
      const bcvVesPerUsd = 40.0;
      const paraleloVesPerUsd = 45.0;

      // Helper: build a fresh single-subscription stream for each test.
      // `Stream.value(...)` is single-subscription so we cannot share one
      // instance across multiple `.first` listeners — each test creates
      // its own.
      Stream<Map<String, double>> mixedAccountsStream() => Stream.value({
            'USD': usdNativeBalance,
            'VES': vesNativeBalance,
          });

      test(
        'BCV: total = 100 USD (native) + 1000/40 = 125 USD',
        () async {
          final helper = CurrencyConversionHelper.forTesting(
            rateLookup: vesUsdRateTable(vesPerUsd: bcvVesPerUsd),
          );

          final result = await helper
              .convertMixedCurrenciesToTarget(
                byNative: mixedAccountsStream(),
                target: policy.displayCurrencies().first, // 'USD'
                source: RateSource.bcv,
              )
              .first;

          expect(result.convertedTotal, closeTo(125.0, 1e-9));
          expect(result.missingRateCurrencies, isEmpty);
        },
      );

      test(
        'Paralelo: total = 100 USD (native) + 1000/45 ≈ 122.22 USD',
        () async {
          final helper = CurrencyConversionHelper.forTesting(
            rateLookup: vesUsdRateTable(vesPerUsd: paraleloVesPerUsd),
          );

          final result = await helper
              .convertMixedCurrenciesToTarget(
                byNative: mixedAccountsStream(),
                target: 'USD',
                source: RateSource.paralelo,
              )
              .first;

          expect(
            result.convertedTotal,
            closeTo(usdNativeBalance + vesNativeBalance / paraleloVesPerUsd, 1e-9),
          );
          expect(result.convertedTotal, lessThan(125.0));
          expect(result.convertedTotal, greaterThan(122.0));
        },
      );

      test(
        'CRITICAL: native USD portion is INVARIANT across BCV ↔ Paralelo '
        'toggle (the absorbed bug)',
        () async {
          // The pre-Phase-9 SQL multiplied EVERY value by the rate (the
          // legacy `t.value * CASE WHEN preferredCurrency …` ladder),
          // which meant toggling BCV ↔ Paralelo also rescaled the native
          // USD portion — visible to the user as "100 USD turns into
          // 112.5 USD when I switch to Paralelo". The Phase 9 fix moved
          // conversion Dart-side so native==target portions pass through
          // verbatim.
          //
          // We assert this by computing both totals and subtracting them:
          // the difference MUST equal the change in the converted-from-VES
          // portion ONLY, with no contribution from the USD-native portion.
          final bcvHelper = CurrencyConversionHelper.forTesting(
            rateLookup: vesUsdRateTable(vesPerUsd: bcvVesPerUsd),
          );
          final paraleloHelper = CurrencyConversionHelper.forTesting(
            rateLookup: vesUsdRateTable(vesPerUsd: paraleloVesPerUsd),
          );

          final bcvResult = await bcvHelper
              .convertMixedCurrenciesToTarget(
                byNative: Stream.value(
                  {'USD': usdNativeBalance, 'VES': vesNativeBalance},
                ),
                target: 'USD',
              )
              .first;
          final paraleloResult = await paraleloHelper
              .convertMixedCurrenciesToTarget(
                byNative: Stream.value(
                  {'USD': usdNativeBalance, 'VES': vesNativeBalance},
                ),
                target: 'USD',
              )
              .first;

          // Expected delta: ONLY the VES-converted portion changes.
          final expectedBcvVesPortion = vesNativeBalance / bcvVesPerUsd;
          final expectedParaleloVesPortion =
              vesNativeBalance / paraleloVesPerUsd;
          final expectedDelta =
              expectedBcvVesPortion - expectedParaleloVesPortion;
          final actualDelta =
              bcvResult.convertedTotal - paraleloResult.convertedTotal;

          expect(
            actualDelta,
            closeTo(expectedDelta, 1e-9),
            reason:
                'Toggle BCV ↔ Paralelo MUST only change the VES-converted '
                'portion. USD-native 100 is invariant — if this delta '
                'matches the VES-only delta, the native portion stayed '
                'fixed at 100 in both cases.',
          );

          // Reality check: each total = 100 (native USD) + (VES portion).
          expect(
            bcvResult.convertedTotal - expectedBcvVesPortion,
            closeTo(usdNativeBalance, 1e-9),
            reason: 'BCV total minus VES-converted portion MUST equal the '
                'native USD balance verbatim.',
          );
          expect(
            paraleloResult.convertedTotal - expectedParaleloVesPortion,
            closeTo(usdNativeBalance, 1e-9),
            reason: 'Paralelo total minus VES-converted portion MUST equal '
                'the native USD balance verbatim.',
          );
        },
      );

      test(
        'policy.rateSourceForPair routes USD↔VES via the user preference',
        () {
          // The dashboard chip drives `preferredVesRateSource` into the
          // helper. Verify the routing is symmetric — both directions of
          // the unordered pair return the chosen source.
          expect(
            policy.rateSourceForPair(
              'USD',
              'VES',
              preferredVesRateSource: RateSource.paralelo,
            ),
            RateSource.paralelo,
          );
          expect(
            policy.rateSourceForPair(
              'VES',
              'USD',
              preferredVesRateSource: RateSource.paralelo,
            ),
            RateSource.paralelo,
          );
          // Default (no pref) → BCV.
          expect(
            policy.rateSourceForPair('USD', 'VES'),
            RateSource.bcv,
          );
        },
      );

      test(
        'RateProviderChain.sourceForPair agrees with policy on USD↔VES',
        () {
          // The chain's static dispatcher and the policy's getter MUST
          // agree on the routing for the dual(USD, VES) flagship case —
          // they are the two entry points the dashboard uses.
          expect(
            RateProviderChain.sourceForPair(
              from: 'USD',
              to: 'VES',
              preferredVesSource: RateSource.bcv,
            ),
            RateSource.bcv,
          );
          expect(
            RateProviderChain.sourceForPair(
              from: 'USD',
              to: 'VES',
              preferredVesSource: RateSource.paralelo,
            ),
            RateSource.paralelo,
          );
        },
      );
    },
  );

  group(
    'Fallback chain integration — Frankfurter → manual → null '
    '(Task 10.3 / 10.5 cross-check)',
    () {
      // Per orchestrator brief 10.3:
      //   - Frankfurter success path → returns rate. (covered: frankfurter_provider_test.dart)
      //   - Frankfurter HTTP 404 → falls back to manual. (covered: frankfurter_provider_test.dart + chain_test)
      //   - Manual missing → returns null + flag. (covered: currency_conversion_helper_test.dart)
      //   - Identity → returns 1.0. (covered: chain_test, helper_test)
      //
      // Here we cross-check the identity + missing-flag invariants flow
      // through the policy → chain → helper composition the same way the
      // dashboard does end-to-end.

      test('Identity USD→USD short-circuits to amount unchanged', () async {
        final helper = CurrencyConversionHelper.forTesting(
          rateLookup: ({
            required String fromCurrency,
            required String toCurrency,
            num amount = 1,
            DateTime? date,
            String? source,
          }) {
            // Identity must short-circuit BEFORE this is reached. If we
            // get here for fromCurrency==toCurrency the helper is broken.
            fail('rateLookup invoked for identity pair $fromCurrency→$toCurrency');
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
      });

      test(
        'Missing rate (Frankfurter 404 + no manual override) surfaces in '
        'missingRateCurrencies set',
        () async {
          final helper = CurrencyConversionHelper.forTesting(
            rateLookup: ({
              required String fromCurrency,
              required String toCurrency,
              num amount = 1,
              DateTime? date,
              String? source,
            }) {
              // Simulate the chain returning null after Frankfurter 404
              // → manual fallback miss.
              return Stream<double?>.value(null);
            },
          );

          final result = await helper
              .convertMixedCurrenciesToTarget(
                byNative: Stream.value({'USD': 100.0, 'JPY': 5000.0}),
                target: 'USD',
              )
              .first;

          // USD portion identity (no rate call), JPY portion missing.
          expect(result.convertedTotal, 100.0);
          expect(result.missingRateCurrencies, contains('JPY'));
          expect(result.hasMissingRates, isTrue);
        },
      );
    },
  );

  group(
    'SingleMode end-to-end — VES base with mixed accounts (Task 10.7 '
    'companion)',
    () {
      test(
        'single_bs with USD account 50 + VES account 500 at BCV=40 → '
        '2500 VES total',
        () async {
          // From transactions/spec.md scenario: under single(VES), a USD
          // account of 50 + a VES account of 500 should resolve to
          //   50 USD * 40 VES/USD + 500 VES = 2500 VES.
          // The native VES portion (500) MUST pass through; only the USD
          // 50 gets converted.
          const policy = SingleMode(code: 'VES');
          expect(policy.displayCurrencies(), ['VES']);

          final helper = CurrencyConversionHelper.forTesting(
            rateLookup: ({
              required String fromCurrency,
              required String toCurrency,
              num amount = 1,
              DateTime? date,
              String? source,
            }) {
              if (fromCurrency == 'USD' && toCurrency == 'VES') {
                return Stream<double?>.value(amount.toDouble() * 40);
              }
              return Stream<double?>.value(null);
            },
          );

          final result = await helper
              .convertMixedCurrenciesToTarget(
                byNative: Stream.value({'USD': 50.0, 'VES': 500.0}),
                target: 'VES',
              )
              .first;

          expect(result.convertedTotal, closeTo(2500.0, 1e-9));
          expect(result.missingRateCurrencies, isEmpty);
        },
      );
    },
  );
}
