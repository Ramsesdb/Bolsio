import 'package:bolsio/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:bolsio/core/services/rate_providers/rate_source.dart';

/// Provider that lets the user override any auto-fetched rate manually.
///
/// Manual rates have priority over any auto source for the same
/// `(currencyCode, date)` tuple in [ExchangeRateService._getRateWithFallback]
/// — the auto refresh job MUST NOT overwrite a manual row (verified at
/// the persistence layer: `insertOrUpdateExchangeRateWithSource` is keyed
/// by `(currencyCode, date, source)`, so manual + auto coexist; readers
/// pick manual first via the chain in
/// `lib/core/services/rate_providers/rate_provider_chain.dart`).
///
/// Crypto pairs default to manual — there's no auto provider for them in
/// scope, so the only way to get a USD↔BTC rate today is for the user to
/// type one in via the Settings screen.
class ManualOverrideProvider {
  ManualOverrideProvider._();
  static final ManualOverrideProvider instance = ManualOverrideProvider._();

  /// Persist a user-entered rate for `from` → `to` on `date` (defaults to
  /// today). Writes a row with `source='manual'`.
  ///
  /// The storage convention mirrors the BCV/Paralelo writers (see
  /// `RateRefreshService._runJob`): the row is keyed by `currencyCode = to`
  /// when the user's preferred currency is `from`, so the column reads as
  /// "1 unit of `currencyCode` = `rate` units of preferred currency".
  ///
  /// To keep this provider decoupled from app state, callers MUST pass
  /// the already-resolved `currencyCode` — the convention check lives at
  /// the dispatch site (`RateProviderChain.setManualRate`).
  Future<int> setManualRate({
    required String currencyCode,
    required double rate,
    DateTime? date,
  }) {
    final when = date ?? DateTime.now();
    return ExchangeRateService.instance.insertOrUpdateExchangeRateWithSource(
      currencyCode: currencyCode,
      date: when,
      rate: rate,
      source: RateSource.manual.dbValue,
    );
  }

  /// Read the latest manual rate for [currencyCode] on or before [date]
  /// (defaults to today). Returns `null` when no manual row exists.
  Stream<double?> getManualRate({
    required String currencyCode,
    DateTime? date,
  }) {
    return ExchangeRateService.instance
        .getLastExchangeRateOf(
          currencyCode: currencyCode,
          date: date,
          source: RateSource.manual.dbValue,
        )
        .map((row) => row?.exchangeRate);
  }
}
