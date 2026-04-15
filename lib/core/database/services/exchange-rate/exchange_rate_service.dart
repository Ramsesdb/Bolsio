import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wallex/core/models/exchange-rate/exchange_rate.dart';
import 'package:wallex/core/services/rate_providers/rate_provider_manager.dart';
import 'package:wallex/core/utils/uuid.dart';
import 'package:rxdart/rxdart.dart';

import '../../app_db.dart';

class ExchangeRateService {
  final AppDB db;

  ExchangeRateService._(this.db);
  static final ExchangeRateService instance = ExchangeRateService._(
    AppDB.instance,
  );

  Future<int> insertOrUpdateExchangeRate(ExchangeRateInDB toInsert) async {
    final elToCompare = (await (getLastExchangeRateOf(
      currencyCode: toInsert.currencyCode,
    )).first);

    if (elToCompare != null &&
        DateUtils.isSameDay(elToCompare.date, toInsert.date)) {
      toInsert = toInsert.copyWith(id: elToCompare.id);
    }

    return db
        .into(db.exchangeRates)
        .insert(toInsert, mode: InsertMode.insertOrReplace);
  }

  /// Insert or update an exchange rate with a specific source tag.
  ///
  /// Looks for an existing rate with the same [currencyCode], same day,
  /// AND same [source]. If found, updates it; otherwise inserts a new row.
  Future<int> insertOrUpdateExchangeRateWithSource({
    required String currencyCode,
    required DateTime date,
    required double rate,
    required String source,
  }) async {
    // Look for existing rate with same currency + date + source
    final existing = await (db.select(db.exchangeRates)
          ..where(
            (e) =>
                e.currencyCode.equals(currencyCode) &
                e.date.date
                    .equals(DateFormat('yyyy-MM-dd').format(date)) &
                e.source.equals(source),
          )
          ..limit(1))
        .getSingleOrNull();

    final toInsert = ExchangeRateInDB(
      id: existing?.id ?? generateUUID(),
      date: date,
      currencyCode: currencyCode,
      exchangeRate: rate,
      source: source,
    );

    return db
        .into(db.exchangeRates)
        .insert(toInsert, mode: InsertMode.insertOrReplace);
  }

  Future<int> deleteExchangeRates({String? currencyCode}) {
    return (db.delete(db.exchangeRates)..where(
          (e) => currencyCode != null
              ? e.currencyCode.equals(currencyCode)
              : e.currencyCode.isNotNull(),
        ))
        .go();
  }

  Future<int> deleteExchangeRateById(String id) {
    return (db.delete(db.exchangeRates)..where((e) => e.id.equals(id))).go();
  }

  /// Get the last exchange rates for all the currencies that the user have in the list of exchange rates
  Stream<List<ExchangeRate>> getExchangeRates({double? limit}) {
    limit ??= -1;

    return db.getLastExchangeRates(limit: limit).watch();
  }

  /// Get all the exchange rates that a currency have in the app
  Stream<ExchangeRate?> getExchangeRateItem(
    String currencyCode,
    DateTime date,
  ) {
    return db
        .getExchangeRates(
          predicate: (e, currency) =>
              e.currencyCode.equals(currencyCode) &
              e.date.date.equals(DateFormat('yyyy-MM-dd').format(date)),
          limit: 1,
        )
        .watchSingleOrNull();
  }

  /// Get all the exchange rates that a currency have in the app
  Stream<List<ExchangeRate>> getExchangeRatesOf(
    String currencyCode, {
    double? limit,
  }) {
    limit ??= -1;

    return db
        .getExchangeRates(
          predicate: (e, currency) => e.currencyCode.equals(currencyCode),
          limit: limit,
        )
        .watch();
  }

  /// Get the last exchange rate before a specified date, for a given currency.
  /// If the date is not provided, the current date is used.
  /// Optionally filter by [source] ('bcv', 'paralelo', etc.).
  Stream<ExchangeRate?> getLastExchangeRateOf({
    required String currencyCode,
    DateTime? date,
    String? source,
  }) {
    date ??= DateTime.now();

    return db
        .getExchangeRates(
          predicate: (e, currency) {
            var condition = e.currencyCode.equals(currencyCode) &
                e.date.isSmallerOrEqualValue(date!);
            if (source != null) {
              condition = condition & e.source.equals(source);
            }
            return condition;
          },
          limit: 1,
        )
        .watchSingleOrNull();
  }

  /// Calculate the exchange rate from [fromCurrency] to the user's preferred
  /// currency. Returns `null` when the rate is unavailable instead of silently
  /// defaulting to 1.0 (which would be catastrophic for VES).
  Stream<double?> calculateExchangeRateToPreferredCurrency({
    required String fromCurrency,
    num amount = 1,
    DateTime? date,
  }) {
    date ??= DateTime.now();

    return getLastExchangeRateOf(currencyCode: fromCurrency, date: date)
        .map((event) => event == null ? null : event.exchangeRate * amount);
  }

  /// Same as [calculateExchangeRateToPreferredCurrency] but returns 0 when
  /// rate is unavailable. Use this ONLY for display widgets that cannot handle
  /// null (account balances, summaries). Do NOT use for transaction sync/storage.
  Stream<double> calculateExchangeRateToPreferredCurrencyOrZero({
    required String fromCurrency,
    num amount = 1,
    DateTime? date,
  }) {
    return calculateExchangeRateToPreferredCurrency(
      fromCurrency: fromCurrency,
      amount: amount,
      date: date,
    ).map((v) => v ?? 0);
  }

  /// Calculate the exchange rate between two currencies.
  /// Returns `null` when either rate is unavailable.
  Stream<double?> calculateExchangeRate({
    required String fromCurrency,
    required String toCurrency,
    num amount = 1,
    DateTime? date,
  }) {
    date ??= DateTime.now();

    final fromExchangeRate = getLastExchangeRateOf(
      currencyCode: fromCurrency,
      date: date,
    );
    final toExchangeRate = getLastExchangeRateOf(
      currencyCode: toCurrency,
      date: date,
    );

    return Rx.combineLatest2(
      fromExchangeRate,
      toExchangeRate,
      (from, to) {
        if (from == null || to == null) return null;
        return (from.exchangeRate / to.exchangeRate) * amount;
      },
    );
  }

  /// Backfill missing exchange rates for a date range using [RateProviderManager].
  ///
  /// For each date in [fromDate]..[toDate] where no rate exists in the DB
  /// for [currencyCode] + [source], fetches via the provider chain and inserts.
  ///
  /// Returns the count of rates successfully inserted.
  Future<int> backfillMissingRates({
    required DateTime fromDate,
    required DateTime toDate,
    String currencyCode = 'USD',
    String source = 'bcv',
  }) async {
    int inserted = 0;
    DateTime current = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime(toDate.year, toDate.month, toDate.day);

    while (!current.isAfter(end)) {
      // Check if rate already exists for this date + currency + source
      final existing = await (db.select(db.exchangeRates)
            ..where(
              (e) =>
                  e.currencyCode.equals(currencyCode) &
                  e.date.date
                      .equals(DateFormat('yyyy-MM-dd').format(current)) &
                  e.source.equals(source),
            )
            ..limit(1))
          .getSingleOrNull();

      if (existing == null) {
        try {
          final result = await RateProviderManager.instance.fetchRate(
            date: current,
            source: source,
          );
          if (result != null) {
            await insertOrUpdateExchangeRateWithSource(
              currencyCode: currencyCode,
              date: current,
              rate: result.rate,
              source: source,
            );
            inserted++;
          }
        } catch (e) {
          debugPrint(
            '[ExchangeRateService] backfill failed for '
            '$currencyCode@$source on $current: $e',
          );
        }
      }

      current = current.add(const Duration(days: 1));
    }

    return inserted;
  }
}
