import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:kilatex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:kilatex/core/services/rate_providers/rate_source.dart';

/// Per-emit conversion outcome — the converted total plus the set of
/// native currencies whose rate was missing.
///
/// Phase 9 of `currency-modes-rework` introduced this so callers can
/// surface "tasa no configurada" hints instead of silently dropping or
/// faking 1:1 conversions (the legacy `?? 1.0` fallback was
/// catastrophic for VES — see design.md §4 / §7).
@immutable
class MixedCurrencyConversionResult {
  /// Sum in [target] currency. Native portions where the rate is missing
  /// are EXCLUDED from this number — callers MUST inspect
  /// [missingRateCurrencies] to know whether to display a hint.
  final double convertedTotal;

  /// Native currencies whose `calculateExchangeRate(native, target, ...)`
  /// returned `null`. Empty when every group converted cleanly.
  final Set<String> missingRateCurrencies;

  const MixedCurrencyConversionResult({
    required this.convertedTotal,
    required this.missingRateCurrencies,
  });

  /// Convenience getter for UI: "tasa no configurada" hint visibility.
  bool get hasMissingRates => missingRateCurrencies.isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MixedCurrencyConversionResult) return false;
    if (other.convertedTotal != convertedTotal) return false;
    if (other.missingRateCurrencies.length != missingRateCurrencies.length) {
      return false;
    }
    return other.missingRateCurrencies.containsAll(missingRateCurrencies);
  }

  @override
  int get hashCode => Object.hash(
    convertedTotal,
    Object.hashAllUnordered(missingRateCurrencies),
  );

  @override
  String toString() =>
      'MixedCurrencyConversionResult(total: $convertedTotal, '
      'missing: $missingRateCurrencies)';
}

/// Sum native-currency amounts after converting non-target portions to
/// [target] using today's rate from [ExchangeRateService.calculateExchangeRate].
///
/// Contract per design.md §7 + transactions spec scenarios:
///   - For each `(native, sumNative)` entry in the input map:
///       * If `native == target`         -> contribute `sumNative` directly (identity, no rate lookup).
///       * Else fetch the rate via [ExchangeRateService.calculateExchangeRate]
///         and contribute `convertedAmount` if the rate is non-null.
///       * Else (rate missing) -> SKIP the contribution and add `native`
///         to [MixedCurrencyConversionResult.missingRateCurrencies].
///   - Empty map -> emits `0.0` with empty missing set.
///   - Stream emits a new result whenever the upstream `byNative` map
///     emits OR any underlying rate stream emits.
///
/// The [source] argument is forwarded to
/// [ExchangeRateService.calculateExchangeRate] as the `:rateSource` hint
/// (the BCV/Paralelo preference for VES pairs). Pass `null` to let the
/// rate service fall back to whichever source is most recent.
///
/// This is the Dart-side replacement for the deleted
/// `t.value * CASE … excRate.exchangeRate` SQL expression in
/// `select-full-data.drift::countTransactions`. Conversion now happens
/// per native group, AFTER the SQL aggregation, so toggling BCV ↔
/// Paralelo only re-converts the non-target portion (the bug was that
/// the legacy SQL also "converted" the native target portion via a
/// `CASE WHEN preferredCurrency` ladder that broke under
/// mode/source toggles).
/// Function shape that resolves a per-currency rate stream for the
/// helper. Mirrors [ExchangeRateService.calculateExchangeRate]'s signature.
/// Tests inject a hand-rolled fake to avoid booting a Drift DB.
typedef RateLookupFn =
    Stream<double?> Function({
      required String fromCurrency,
      required String toCurrency,
      num amount,
      DateTime? date,
      String? source,
    });

class CurrencyConversionHelper {
  CurrencyConversionHelper._({RateLookupFn? rateLookup})
    : _rateLookup =
          rateLookup ??
          (({
            required String fromCurrency,
            required String toCurrency,
            num amount = 1,
            DateTime? date,
            String? source,
          }) =>
              ExchangeRateService.instance.calculateExchangeRate(
                fromCurrency: fromCurrency,
                toCurrency: toCurrency,
                amount: amount,
                date: date,
                source: source,
              ));

  static final CurrencyConversionHelper instance = CurrencyConversionHelper._();

  /// Test-only factory — lets unit tests inject a fake rate-lookup
  /// function without touching the [ExchangeRateService] singleton.
  @visibleForTesting
  factory CurrencyConversionHelper.forTesting({
    required RateLookupFn rateLookup,
  }) {
    return CurrencyConversionHelper._(rateLookup: rateLookup);
  }

  final RateLookupFn _rateLookup;

  /// Stream variant — re-emits whenever [byNative] OR any underlying
  /// rate stream emits. See class doc for the conversion contract.
  ///
  /// The [source] argument should be the user's
  /// [RateSource.dbValue] for the VES pair (or `null` for the auto chain).
  Stream<MixedCurrencyConversionResult> convertMixedCurrenciesToTarget({
    required Stream<Map<String, double>> byNative,
    required String target,
    RateSource? source,
    DateTime? date,
  }) {
    final upperTarget = target.toUpperCase();
    return byNative.switchMap((map) {
      if (map.isEmpty) {
        return Stream.value(
          const MixedCurrencyConversionResult(
            convertedTotal: 0.0,
            missingRateCurrencies: <String>{},
          ),
        );
      }

      // Bucket entries: native==target stays as a constant; the rest go
      // through `calculateExchangeRate`.
      double nativeContribution = 0.0;
      final perCurrencyStreams = <Stream<({String code, double? amount})>>[];

      for (final entry in map.entries) {
        final code = entry.key.toUpperCase();
        final amount = entry.value;
        if (code == upperTarget) {
          nativeContribution += amount;
          continue;
        }
        final converted$ = _rateLookup(
          fromCurrency: code,
          toCurrency: upperTarget,
          amount: amount,
          date: date,
          source: source?.dbValue,
        ).map(
          (converted) => (code: code, amount: converted),
        );
        perCurrencyStreams.add(converted$);
      }

      if (perCurrencyStreams.isEmpty) {
        return Stream.value(
          MixedCurrencyConversionResult(
            convertedTotal: nativeContribution,
            missingRateCurrencies: const <String>{},
          ),
        );
      }

      return Rx.combineLatestList(perCurrencyStreams).map((results) {
        var total = nativeContribution;
        final missing = <String>{};
        for (final r in results) {
          final amount = r.amount;
          if (amount == null) {
            missing.add(r.code);
          } else {
            total += amount;
          }
        }
        return MixedCurrencyConversionResult(
          convertedTotal: total,
          missingRateCurrencies: missing,
        );
      });
    });
  }

  /// Convenience: emits just the converted total (drops the missing-set
  /// side-channel). Use this for callers that already had a `Stream<double>`
  /// shape and don't yet wire a "tasa no configurada" hint into their UI.
  ///
  /// NOTE: native portions where the rate is missing are EXCLUDED from
  /// the total. They do NOT silently fall back to 1.0 (the
  /// `currency-modes-rework` decision #6 behaviour). Callers that need
  /// to surface the missing-rate count MUST use the full
  /// [convertMixedCurrenciesToTarget] variant.
  Stream<double> convertMixedCurrenciesToTotal({
    required Stream<Map<String, double>> byNative,
    required String target,
    RateSource? source,
    DateTime? date,
  }) {
    return convertMixedCurrenciesToTarget(
      byNative: byNative,
      target: target,
      source: source,
      date: date,
    ).map((r) => r.convertedTotal);
  }
}
