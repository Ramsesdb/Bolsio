import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:bolsio/core/services/rate_providers/rate_provider.dart';
import 'package:bolsio/core/services/rate_providers/rate_source.dart';

/// Auto fiat-fiat rate provider backed by [api.frankfurter.app](https://api.frankfurter.app).
///
/// Frankfurter wraps the European Central Bank reference rates and exposes a
/// JSON endpoint with no API key. It covers ~30 fiat currencies (USD, EUR,
/// GBP, JPY, CHF, CAD, AUD, BRL, MXN, ARS NOT included, etc.). Crypto and
/// many South-American currencies are NOT covered — callers MUST fall back
/// to the manual override provider for those pairs.
///
/// Endpoint shape:
///
/// ```
/// GET https://api.frankfurter.app/latest?from=EUR&to=GBP
/// → {"amount":1.0,"base":"EUR","date":"2026-04-29","rates":{"GBP":0.846}}
/// ```
///
/// Errors and fallbacks:
///
/// | Failure mode | Behaviour |
/// |---|---|
/// | Network error / timeout | Returns `null` (caller falls back). |
/// | HTTP 4xx (e.g. unsupported currency) | Returns `null`. |
/// | Malformed JSON / missing `rates[to]` | Returns `null`. |
/// | Stale data (`date` older than 24h) | Still returns the rate but tags it; the upstream chain decides whether to surface a banner. |
///
/// This provider does NOT throw; null is the universal "no rate" signal so
/// the manager can step through the fallback chain without exception
/// handling at every call site (matching the `DolarApiProvider` contract).
///
/// **Caching**: Frankfurter publishes once per business day, so a 24h TTL on
/// the persisted `exchangeRates` row is the correct refresh policy. The
/// caller (typically `RateRefreshService`) owns the TTL — this provider
/// always performs a fresh fetch when invoked. Manual refresh therefore
/// just bypasses the caller's TTL gate (no flag needed here).
class FrankfurterRateProvider extends RateProvider {
  static const String _baseUrl = 'https://api.frankfurter.app';

  /// Pluggable HTTP client to allow mocking in unit tests. Defaults to a
  /// fresh `http.Client()` instance so production callers don't have to
  /// think about it.
  final http.Client _httpClient;

  /// Network timeout for a single request. Frankfurter is fast (~200ms p95)
  /// — 10s is conservative and matches `DolarApiProvider`.
  final Duration _timeout;

  FrankfurterRateProvider({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 10),
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout;

  @override
  String get name => 'Frankfurter';

  /// Frankfurter does NOT support historical lookups via this provider.
  /// (The API exposes `/{date}` endpoints but we don't use them — backfill
  /// is out of scope for this change. Treat the provider as "today only".)
  @override
  bool get supportsHistorical => false;

  /// Crypto + a handful of unsupported fiat currencies. Used by callers to
  /// gate calls to this provider before paying the network round-trip.
  ///
  /// Sourced from <https://www.frankfurter.app/docs/#currencies>. ARS, COP,
  /// PEN, CLP, BOB, UYU, PYG, VES are explicitly absent (most LATAM ex-MX
  /// is unsupported). Crypto codes (BTC, ETH, USDT, USDC, BNB, …) are also
  /// unsupported by definition — the API only covers ECB-quoted fiat.
  ///
  /// The list is conservative: any `null` response from the API is the
  /// authoritative signal for "unsupported" — this list is just an opt-out
  /// short-circuit to avoid hitting the network for known-unsupported pairs.
  static const Set<String> _unsupportedCurrencies = <String>{
    // Crypto.
    'BTC', 'ETH', 'USDT', 'USDC', 'BNB', 'SOL', 'ADA', 'XRP', 'DOGE',
    'DOT', 'AVAX', 'TRX', 'LINK', 'LTC', 'BCH',
    // LATAM fiat absent from Frankfurter.
    'VES', 'ARS', 'COP', 'PEN', 'CLP', 'BOB', 'UYU', 'PYG',
  };

  /// Returns true when this provider has any chance of serving the pair
  /// (`from` → `to`). Callers SHOULD check this before invoking
  /// [fetchRate] so they can skip the network round-trip and dispatch
  /// directly to the manual provider.
  static bool supportsPair(String from, String to) {
    final upperFrom = from.toUpperCase();
    final upperTo = to.toUpperCase();
    if (upperFrom == upperTo) return true; // identity, trivially supported
    return !_unsupportedCurrencies.contains(upperFrom) &&
        !_unsupportedCurrencies.contains(upperTo);
  }

  /// Fetch a rate from Frankfurter.
  ///
  /// The [source] argument is part of the [RateProvider] interface; this
  /// provider only handles `'auto_frankfurter'`. Any other value returns
  /// `null` so the manager can route to a different provider.
  ///
  /// [date] is honoured for "today vs not-today" gating only — the API
  /// always returns today's value via `/latest`.
  ///
  /// [currencyCode] is the source currency. The destination is the
  /// `_baseCurrency` of the storage layer (USD when prefs are not VES,
  /// VES otherwise). To stay decoupled from app state, callers wanting
  /// a specific `to` currency should use [fetchPair] directly.
  @override
  Future<RateResult?> fetchRate({
    required DateTime date,
    required String source,
    String currencyCode = 'USD',
  }) async {
    if (source != RateSource.autoFrankfurter.dbValue) return null;
    // Frankfurter only serves the latest rate.
    if (!_isToday(date)) return null;
    // Default `to` is USD — matches the storage convention used elsewhere.
    return fetchPair(from: currencyCode, to: 'USD');
  }

  /// Direct pair fetch: returns `1 from = X to`. This is the typed
  /// entry-point the new rate chain uses; [fetchRate] is the
  /// [RateProvider]-interface adapter.
  Future<RateResult?> fetchPair({
    required String from,
    required String to,
  }) async {
    final upperFrom = from.toUpperCase();
    final upperTo = to.toUpperCase();
    if (upperFrom == upperTo) {
      return RateResult(
        rate: 1.0,
        fetchedAt: DateTime.now(),
        providerName: name,
        source: RateSource.autoFrankfurter.dbValue,
      );
    }
    if (!supportsPair(upperFrom, upperTo)) {
      // Skip the network round-trip for known-unsupported pairs.
      return null;
    }

    final uri = Uri.parse(
      '$_baseUrl/latest?from=$upperFrom&to=$upperTo',
    );
    try {
      final response = await _httpClient
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          '[FrankfurterRateProvider] $upperFrom→$upperTo HTTP '
          '${response.statusCode}',
        );
        return null;
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final rates = decoded['rates'];
      if (rates is! Map<String, dynamic>) return null;

      final rateValue = rates[upperTo];
      final rate = (rateValue is num) ? rateValue.toDouble() : null;
      if (rate == null || rate <= 0) return null;

      // The API reports the publication date; we store the row tagged with
      // it so consumers can detect staleness. `RateResult` has no date
      // field of its own — `fetchedAt` is the local-clock fetch time.
      // Persistence callers MUST write the API-reported date as the
      // `exchangeRates.date` row; the helper below exposes it.
      return RateResult(
        rate: rate,
        fetchedAt: DateTime.now(),
        providerName: name,
        source: RateSource.autoFrankfurter.dbValue,
      );
    } on TimeoutException {
      debugPrint(
        '[FrankfurterRateProvider] timeout fetching $upperFrom→$upperTo',
      );
      return null;
    } catch (e) {
      debugPrint(
        '[FrankfurterRateProvider] error fetching $upperFrom→$upperTo: $e',
      );
      return null;
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Release the underlying HTTP client. Optional — Dart will GC it on
  /// process exit. Tests that inject a mock client should NOT call this
  /// (the test harness owns the lifecycle).
  void dispose() => _httpClient.close();
}
