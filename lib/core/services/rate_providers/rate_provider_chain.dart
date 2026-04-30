import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bolsio/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:bolsio/core/services/rate_providers/frankfurter_provider.dart';
import 'package:bolsio/core/services/rate_providers/manual_override_provider.dart';
import 'package:bolsio/core/services/rate_providers/rate_source.dart';

/// Outcome of a chain dispatch — the rate plus which step in the fallback
/// chain produced it (so callers can drive UI hints like "tasa
/// desactualizada" / "tasa no configurada" without re-deriving the chain).
@immutable
class ChainResult {
  final double rate;
  final RateSource source;
  final DateTime fetchedAt;

  /// True when the value comes from a manual override fallback because the
  /// upstream auto provider failed. Drives the "tasa automática no
  /// disponible" banner in the UI.
  final bool fellBackToManual;

  const ChainResult({
    required this.rate,
    required this.source,
    required this.fetchedAt,
    this.fellBackToManual = false,
  });
}

/// Chain dispatcher that picks the right provider for a given pair and
/// falls back gracefully when the primary fails.
///
/// Decision tree (per design §4):
///
/// ```
/// pair (from, to):
///   identity (from == to)               -> trivially 1.0, source=manual sentinel
///   pair contains VES                   -> bcv | paralelo (per [preferredVesSource])
///   crypto pair OR unsupported by FF    -> manual
///   fiat-fiat & supported by FF         -> auto_frankfurter -> manual fallback
/// ```
///
/// The chain does NOT manage policy state — it takes the user's preferred
/// VES rate source as an explicit argument. The caller (typically
/// `RateRefreshService` or the Settings screen) reads
/// `appStateSettings[SettingKey.preferredRateSource]` once and passes it
/// in. Keeping the chain stateless makes it trivially testable.
class RateProviderChain {
  RateProviderChain._({
    FrankfurterRateProvider? frankfurter,
    ManualOverrideProvider? manual,
    SharedPreferencesAsync? prefs,
  })  : _frankfurter = frankfurter ?? FrankfurterRateProvider(),
        _manual = manual ?? ManualOverrideProvider.instance,
        _prefs = prefs ?? SharedPreferencesAsync();

  static final RateProviderChain instance = RateProviderChain._();

  /// Test-only factory that lets unit tests inject mocks for every layer
  /// without touching the singleton. NOT part of the public API.
  ///
  /// VES rates (BCV / Paralelo) are NOT injectable here — the chain reads
  /// them straight from the persisted `exchangeRates` table, which is
  /// owned by `RateRefreshService`. Tests that exercise VES paths should
  /// pre-seed rows via `ExchangeRateService.insertOrUpdateExchangeRateWithSource`.
  @visibleForTesting
  factory RateProviderChain.forTesting({
    FrankfurterRateProvider? frankfurter,
    ManualOverrideProvider? manual,
    SharedPreferencesAsync? prefs,
  }) {
    return RateProviderChain._(
      frankfurter: frankfurter,
      manual: manual,
      prefs: prefs,
    );
  }

  final FrankfurterRateProvider _frankfurter;
  final ManualOverrideProvider _manual;
  final SharedPreferencesAsync _prefs;

  /// 24h staleness window for Frankfurter. Manual rates are NEVER stale
  /// (the user vouched for them). BCV/Paralelo TTL stays in
  /// [RateRefreshService] which already gates at 12h.
  static const Duration _frankfurterTtl = Duration(hours: 24);

  /// Pick the right [RateSource] for a pair, given the user's VES
  /// preference. Pure function — no I/O.
  ///
  /// Returns `null` for the identity case (`from == to`); callers MUST
  /// short-circuit to `1.0` without dispatching.
  static RateSource? sourceForPair({
    required String from,
    required String to,
    RateSource? preferredVesSource,
  }) {
    final upperFrom = from.toUpperCase();
    final upperTo = to.toUpperCase();
    if (upperFrom == upperTo) return null;

    final pair = {upperFrom, upperTo};
    if (pair.contains('VES') && pair.contains('USD')) {
      return preferredVesSource ?? RateSource.bcv;
    }
    if (pair.contains('VES')) {
      // VES paired with non-USD: no auto provider supports this directly;
      // fall back to manual until a chain-of-rates infra lands.
      return RateSource.manual;
    }
    if (FrankfurterRateProvider.supportsPair(upperFrom, upperTo)) {
      return RateSource.autoFrankfurter;
    }
    return RateSource.manual;
  }

  /// Crypto-or-unsupported short-circuit: any pair containing a known
  /// crypto code (BTC, ETH, USDT, …) goes straight to manual without an
  /// API call. This keeps Frankfurter from being hit with junk and makes
  /// the manual flow the only configuration surface for crypto.
  ///
  /// **Phase 4.6**: this is the single place where the "crypto defaults
  /// to manual" rule is enforced. Any future refactor that touches the
  /// chain MUST preserve this short-circuit.
  static bool isCryptoOrUnsupported(String from, String to) {
    return !FrankfurterRateProvider.supportsPair(
      from.toUpperCase(),
      to.toUpperCase(),
    );
  }

  /// Fetch a rate for `from` → `to` on `date` (defaults to today),
  /// dispatching through the chain.
  ///
  /// - [preferredVesSource]: user's BCV/Paralelo choice. Ignored unless
  ///   the pair involves VES.
  /// - [force]: when `true`, bypass the 24h staleness gate and force a
  ///   fresh network call (Frankfurter only — BCV/Paralelo TTL is owned
  ///   by [RateRefreshService]).
  /// - [persistAuto]: when `true` (default), a successful auto fetch is
  ///   persisted to `exchangeRates`. Disable in test paths or one-shot
  ///   reads.
  ///
  /// Returns `null` when every provider in the chain fails — the caller
  /// MUST surface a "tasa no configurada" hint to the user. Callers that
  /// need a non-null double for display arithmetic should use
  /// `ExchangeRateService.calculateExchangeRateOrZero` instead.
  Future<ChainResult?> fetchRate({
    required String from,
    required String to,
    DateTime? date,
    RateSource? preferredVesSource,
    bool force = false,
    bool persistAuto = true,
  }) async {
    final upperFrom = from.toUpperCase();
    final upperTo = to.toUpperCase();
    final when = date ?? DateTime.now();

    // Identity short-circuit.
    if (upperFrom == upperTo) {
      return ChainResult(
        rate: 1.0,
        source: RateSource.manual,
        fetchedAt: when,
      );
    }

    final picked = sourceForPair(
      from: upperFrom,
      to: upperTo,
      preferredVesSource: preferredVesSource,
    );
    if (picked == null) {
      // Should not happen given the identity short-circuit, but keeps the
      // null-safety contract honest.
      return null;
    }

    switch (picked) {
      case RateSource.bcv:
      case RateSource.paralelo:
        return _fetchVes(
          from: upperFrom,
          to: upperTo,
          date: when,
          source: picked,
          persistAuto: persistAuto,
        );
      case RateSource.autoFrankfurter:
        return _fetchFrankfurterWithFallback(
          from: upperFrom,
          to: upperTo,
          date: when,
          force: force,
          persistAuto: persistAuto,
        );
      case RateSource.manual:
        return _fetchManual(from: upperFrom, to: upperTo, date: when);
    }
  }

  /// Persist a manual rate. Convenience wrapper around
  /// [ManualOverrideProvider.setManualRate] that handles the
  /// `currencyCode` resolution (the "non-base" currency in the pair).
  ///
  /// Manual rate semantics: the user enters "1 [from] = [rate] [to]".
  /// The storage row is `currencyCode = [storeCurrency]` with rate
  /// expressed as "1 [storeCurrency] = X [baseCurrency]".
  /// [baseCurrency] should be the user's preferred currency (USD or VES);
  /// [storeCurrency] is the non-preferred half of the pair.
  ///
  /// Example: user is preferred=USD and enters BTC = 50000 USD.
  /// Caller passes `(from: 'BTC', to: 'USD', rate: 50000.0,
  /// baseCurrency: 'USD')` → row is `(currencyCode: 'BTC', rate: 50000)`.
  Future<int> setManualRate({
    required String from,
    required String to,
    required double rate,
    required String baseCurrency,
    DateTime? date,
  }) {
    final upperFrom = from.toUpperCase();
    final upperTo = to.toUpperCase();
    final upperBase = baseCurrency.toUpperCase();

    final String storeCurrency;
    final double storeRate;
    if (upperFrom == upperBase) {
      // 1 USD = X BTC → store in BTC row as 1 BTC = 1/X USD
      storeCurrency = upperTo;
      storeRate = rate == 0 ? 0 : 1.0 / rate;
    } else {
      storeCurrency = upperFrom;
      storeRate = rate;
    }

    return _manual.setManualRate(
      currencyCode: storeCurrency,
      rate: storeRate,
      date: date,
    );
  }

  // ── private dispatchers ─────────────────────────────────────────────────

  Future<ChainResult?> _fetchVes({
    required String from,
    required String to,
    required DateTime date,
    required RateSource source,
    required bool persistAuto,
  }) async {
    // VES pairs have a separate scheduler (RateRefreshService); the chain
    // just reads the most recent persisted row. If none exists, fall back
    // to a manual row before giving up.
    final row = await ExchangeRateService.instance
        .getLastExchangeRateOf(
          currencyCode: _nonBaseCurrency(from: from, to: to),
          date: date,
          source: source.dbValue,
        )
        .first;
    if (row != null) {
      return ChainResult(
        rate: row.exchangeRate,
        source: source,
        fetchedAt: row.date,
      );
    }
    final manual = await _fetchManual(from: from, to: to, date: date);
    if (manual != null) {
      return ChainResult(
        rate: manual.rate,
        source: RateSource.manual,
        fetchedAt: manual.fetchedAt,
        fellBackToManual: true,
      );
    }
    return null;
  }

  Future<ChainResult?> _fetchFrankfurterWithFallback({
    required String from,
    required String to,
    required DateTime date,
    required bool force,
    required bool persistAuto,
  }) async {
    // Crypto pairs MUST never reach here (sourceForPair short-circuits
    // them to manual), but guard anyway for defence in depth.
    if (isCryptoOrUnsupported(from, to)) {
      return _fellBackManual(from: from, to: to, date: date);
    }

    // 1. Cache hit?
    if (!force) {
      final cached = await _readFreshFrankfurterRow(
        from: from,
        to: to,
        date: date,
      );
      if (cached != null) return cached;
    }

    // 2. Live fetch.
    final live = await _frankfurter.fetchPair(from: from, to: to);
    if (live != null) {
      if (persistAuto) {
        await ExchangeRateService.instance
            .insertOrUpdateExchangeRateWithSource(
          currencyCode: from,
          date: date,
          rate: live.rate,
          source: RateSource.autoFrankfurter.dbValue,
        );
        await _setFrankfurterFetchTimestamp(from: from, to: to, when: date);
      }
      return ChainResult(
        rate: live.rate,
        source: RateSource.autoFrankfurter,
        fetchedAt: live.fetchedAt,
      );
    }

    // 3. Fallback to manual.
    return _fellBackManual(from: from, to: to, date: date);
  }

  Future<ChainResult?> _fetchManual({
    required String from,
    required String to,
    required DateTime date,
  }) async {
    final manualRate = await _manual
        .getManualRate(currencyCode: from, date: date)
        .first;
    if (manualRate != null) {
      return ChainResult(
        rate: manualRate,
        source: RateSource.manual,
        fetchedAt: date,
      );
    }
    // Try the inverse direction.
    final inverse = await _manual
        .getManualRate(currencyCode: to, date: date)
        .first;
    if (inverse != null && inverse != 0) {
      return ChainResult(
        rate: 1.0 / inverse,
        source: RateSource.manual,
        fetchedAt: date,
      );
    }
    return null;
  }

  Future<ChainResult?> _fellBackManual({
    required String from,
    required String to,
    required DateTime date,
  }) async {
    final manual = await _fetchManual(from: from, to: to, date: date);
    if (manual == null) return null;
    return ChainResult(
      rate: manual.rate,
      source: RateSource.manual,
      fetchedAt: manual.fetchedAt,
      fellBackToManual: true,
    );
  }

  /// Read a Frankfurter row only when its persisted fetch timestamp is
  /// younger than the 24h TTL. Returns `null` when no row exists OR the
  /// row is stale — in either case, the caller will fetch fresh.
  Future<ChainResult?> _readFreshFrankfurterRow({
    required String from,
    required String to,
    required DateTime date,
  }) async {
    final row = await ExchangeRateService.instance
        .getLastExchangeRateOf(
          currencyCode: from,
          date: date,
          source: RateSource.autoFrankfurter.dbValue,
        )
        .first;
    if (row == null) return null;
    final ts = await _readFrankfurterFetchTimestamp(from: from, to: to);
    if (ts == null) return null;
    if (DateTime.now().difference(ts) > _frankfurterTtl) return null;
    return ChainResult(
      rate: row.exchangeRate,
      source: RateSource.autoFrankfurter,
      fetchedAt: ts,
    );
  }

  Future<DateTime?> _readFrankfurterFetchTimestamp({
    required String from,
    required String to,
  }) async {
    final raw = await _prefs.getString(_frankfurterTtlKey(from: from, to: to));
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _setFrankfurterFetchTimestamp({
    required String from,
    required String to,
    required DateTime when,
  }) {
    return _prefs.setString(
      _frankfurterTtlKey(from: from, to: to),
      when.toIso8601String(),
    );
  }

  String _frankfurterTtlKey({required String from, required String to}) {
    return 'frankfurterLastFetched_${from}_$to';
  }

  /// For VES pairs, the "non-base" currency is the one whose row we
  /// actually read. The convention from `RateRefreshService._runJob`:
  /// when preferred=VES we store USD rows; when preferred=USD we store
  /// VES rows. The chain only needs the non-base half — it's whichever
  /// of `from`/`to` is NOT VES (or NOT USD, when preferred is VES).
  ///
  /// Heuristic without app-state coupling: the pair contains exactly USD
  /// and VES; pick whichever is not VES first (because in the dominant
  /// case preferred=USD, the row lives under VES). If preferred is VES,
  /// the resolution still works because [getLastExchangeRateOf] would
  /// also have stored rows under USD.
  String _nonBaseCurrency({required String from, required String to}) {
    if (from == 'VES') return to;
    if (to == 'VES') return from;
    return from;
  }
}
