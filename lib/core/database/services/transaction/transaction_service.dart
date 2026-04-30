import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:kilatex/core/database/app_db.dart';
import 'package:kilatex/core/database/services/account/account_service.dart';
import 'package:kilatex/core/services/attachments/attachment_model.dart';
import 'package:kilatex/core/services/attachments/attachments_service.dart';
import 'package:kilatex/core/database/utils/drift_utils.dart';
import 'package:kilatex/core/models/account/account.dart';
import 'package:kilatex/core/models/transaction/transaction.dart';
import 'package:kilatex/core/models/transaction/transaction_status.enum.dart';
import 'package:kilatex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/services/currency/currency_conversion_helper.dart';
import 'package:kilatex/core/services/firebase_sync_service.dart';
import 'package:kilatex/core/services/rate_providers/rate_source.dart';
import 'package:rxdart/rxdart.dart';

import '../../../models/transaction/transaction_type.enum.dart';

class TransactionQueryStatResult {
  int numberOfRes;
  double valueSum;

  TransactionQueryStatResult({
    required this.numberOfRes,
    required this.valueSum,
  });
}

/// Per-Phase-9 envelope for callers that need to surface a "tasa no
/// configurada" hint alongside the count + converted balance.
///
/// `valueSum` excludes contributions from any [missingRateCurrencies]
/// (consistent with the new `calculateExchangeRate` contract — no silent
/// `?? 1.0` fallback). Callers that present the balance to the user
/// SHOULD render a hint when [missingRateCurrencies] is non-empty so the
/// user understands that the displayed total is partial.
class TransactionQueryStatResultWithMissing {
  final int numberOfRes;
  final double valueSum;
  final Set<String> missingRateCurrencies;

  TransactionQueryStatResultWithMissing({
    required this.numberOfRes,
    required this.valueSum,
    required this.missingRateCurrencies,
  });

  bool get hasMissingRates => missingRateCurrencies.isNotEmpty;
}

typedef TransactionQueryOrderBy =
    OrderBy Function(
      Transactions transaction,
      Accounts account,
      Currencies accountCurrency,
      Accounts receivingAccount,
      Currencies receivingAccountCurrency,
      Categories c,
      Categories,
    );

class TransactionService {
  final AppDB db;
  final AttachmentsService attachmentsService;

  TransactionService._(this.db, {AttachmentsService? attachmentsService})
      : attachmentsService = attachmentsService ?? AttachmentsService.instance;

  TransactionService.forTesting(
    this.db, {
    required this.attachmentsService,
  });

  static final TransactionService instance = TransactionService._(
    AppDB.instance,
  );

  /// Create a transaction atomically with audit log
  Future<int> insertTransaction(TransactionInDB transaction) async {
    return db.transaction(() async {
      final toReturn = await db.into(db.transactions).insert(transaction);

      // Push to organization collection for multi-device sync (Fire and forget)
      unawaited(FirebaseSyncService.instance.pushTransaction(transaction));

      // To update the getAccountsData() function results
      db.markTablesUpdated([db.accounts, db.transactions]);

      return toReturn;
    });
  }

  /// Update a transaction atomically with audit log
  Future<int> updateTransaction(TransactionInDB transaction) async {
    return db.transaction(() async {
      final toReturn = await db.update(db.transactions).replace(transaction);

      // Push to organization collection for multi-device sync (Fire and forget)
      unawaited(FirebaseSyncService.instance.pushTransaction(transaction));

      // To update the getAccountsData() function results
      db.markTablesUpdated([db.accounts, db.transactions]);

      return toReturn ? 1 : 0;
    });
  }

  /// Updates a recurrent transaction to its next payment iteration.
  ///
  /// This function updates a given recurrent transaction by advancing its date
  /// to the next scheduled payment and decrementing the remaining iterations count,
  /// if applicable. The updated transaction is then saved to the database.
  Future<int> setTransactionNextPayment(MoneyTransaction transaction) {
    int? remainingIterations =
        transaction.recurrentInfo.ruleRecurrentLimit!.remainingIterations;

    return TransactionService.instance.updateTransaction(
      transaction.copyWith(
        date: transaction.followingDateToNext,
        remainingTransactions: remainingIterations != null
            ? Value(remainingIterations - 1)
            : const Value(null),
      ),
    );
  }

  /// Delete a transaction atomically with audit log
  Future<int> deleteTransaction(String transactionId) async {
    return db.transaction(() async {
      // Delete from organization collection for multi-device sync (Fire and forget)
      unawaited(FirebaseSyncService.instance.deleteTransaction(transactionId));

      // Keep attachments in sync with transaction lifecycle.
      await attachmentsService.deleteByOwner(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: transactionId,
      );

      final result = await (db.delete(
        db.transactions,
      )..where((tbl) => tbl.id.equals(transactionId))).go();

      // Notify streams watching these tables to update balance displays
      db.markTablesUpdated([db.accounts, db.transactions]);

      return result;
    });
  }

  Stream<List<MoneyTransaction>> getTransactionsFromPredicate({
    Expression<bool> Function(
      Transactions,
      Accounts,
      Currencies,
      Accounts,
      Currencies,
      Categories,
      Categories,
    )?
    predicate,
    OrderBy Function(
      Transactions transaction,
      Accounts account,
      Currencies accountCurrency,
      Accounts receivingAccount,
      Currencies receivingAccountCurrency,
      Categories c,
      Categories,
    )?
    orderBy,
    int? limit,
    int? offset,
  }) {
    return db
        .getTransactionsWithFullData(
          predicate: predicate,
          preferredCurrency:
              appStateSettings[SettingKey.preferredCurrency] ?? 'USD',
          rateSource:
              appStateSettings[SettingKey.preferredRateSource] ?? 'bcv',
          orderBy: orderBy,
          limit: (t, a, accountCurrency, ra, receivingAccountCurrency, c, pc) =>
              Limit(limit ?? -1, offset),
        )
        .watch();
  }

  /// Get transactions from the DB based on some filters.
  ///
  /// By default, the transactions will be returned ordered by date
  Stream<List<MoneyTransaction>> getTransactions({
    TransactionFilterSet? filters,
    TransactionQueryOrderBy? orderBy,
    int? limit,
    int? offset,
  }) {
    return getTransactionsFromPredicate(
      predicate: filters?.toTransactionExpression(),
      orderBy:
          orderBy ??
          (p0, p1, p2, p3, p4, p5, p6) => OrderBy([
            OrderingTerm(expression: p0.date, mode: OrderingMode.desc),
          ]),
      limit: limit,
      offset: offset,
    );
  }

  Stream<int> countTransactions({
    TransactionFilterSet filters = const TransactionFilterSet(),
    bool convertToPreferredCurrency = true,
    DateTime? exchDate,
  }) {
    return _countTransactions(
      predicate: filters,
      convertToPreferredCurrency: convertToPreferredCurrency,
      exchDate: exchDate,
    ).map((event) => event.numberOfRes);
  }

  Stream<double> getTransactionsValueBalance({
    TransactionFilterSet filters = const TransactionFilterSet(),
    bool convertToPreferredCurrency = true,
    DateTime? exchDate,
  }) {
    filters = filters.copyWith(
      status: TransactionStatus.getStatusThatCountsForStats(filters.status),
    );

    return _countTransactions(
      predicate: filters,
      convertToPreferredCurrency: convertToPreferredCurrency,
      exchDate: exchDate,
    ).map((event) => event.valueSum);
  }

  /// Per-Phase-9 sibling of [countTransactions] + [getTransactionsValueBalance]
  /// that surfaces the missing-rate side-channel from
  /// [CurrencyConversionHelper] alongside the count + converted balance.
  ///
  /// Callers that previously did `Rx.combineLatest2(countTransactions(...),
  /// getTransactionsValueBalance(...))` SHOULD migrate to this method and
  /// render a "tasa no configurada" hint when
  /// [TransactionQueryStatResultWithMissing.hasMissingRates] is true. See
  /// design.md §7 (Phase 9 caller-audit).
  ///
  /// The returned `valueSum` is converted to the user's
  /// preferred currency and EXCLUDES native portions whose rate is
  /// missing — identical behaviour to [getTransactionsValueBalance], but
  /// with the missing-currency Set exposed so the UI can flag the user.
  Stream<TransactionQueryStatResultWithMissing>
      getTransactionsCountAndBalanceWithMissing({
    TransactionFilterSet filters = const TransactionFilterSet(),
    DateTime? exchDate,
  }) {
    filters = filters.copyWith(
      status: TransactionStatus.getStatusThatCountsForStats(filters.status),
    );

    final String target =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
    final RateSource rateSource = RateSource.fromDb(
      appStateSettings[SettingKey.preferredRateSource],
    );

    // We re-derive the count + per-native map at the wrapper level so we
    // can route the map through the helper's full
    // `convertMixedCurrenciesToTarget` (which exposes the missing set)
    // instead of the count-collapsed `convertMixedCurrenciesToTotal`.
    return _countByNativeStreamCombined(filters: filters)
        .switchMap((stat) {
      return CurrencyConversionHelper.instance
          .convertMixedCurrenciesToTarget(
            byNative: Stream.value(stat.byNative),
            target: target,
            source: rateSource,
            date: exchDate,
          )
          .map(
            (result) => TransactionQueryStatResultWithMissing(
              numberOfRes: stat.count,
              valueSum: result.convertedTotal,
              missingRateCurrencies: result.missingRateCurrencies,
            ),
          );
    });
  }

  /// Phase 6 of `currency-modes-rework`: stream the converted balance to
  /// an arbitrary [targetCurrency] (NOT the user's preferred currency).
  ///
  /// Used by dashboard widgets that render a `DualMode` policy — the
  /// secondary line targets `policy.secondary` directly, which may differ
  /// from `appStateSettings[SettingKey.preferredCurrency]`.
  ///
  /// Returns the converted total (or `null` when no transactions match
  /// the filter). Native portions in [targetCurrency] are NEVER multiplied
  /// by a rate — they pass through verbatim (the bug the rework absorbs).
  /// Foreign portions whose rate is missing are EXCLUDED (no silent
  /// `?? 1.0` fallback).
  Stream<double?> getValueBalanceForTarget({
    TransactionFilterSet filters = const TransactionFilterSet(),
    required String targetCurrency,
    DateTime? exchDate,
  }) {
    filters = filters.copyWith(
      status: TransactionStatus.getStatusThatCountsForStats(filters.status),
    );

    final RateSource rateSource = RateSource.fromDb(
      appStateSettings[SettingKey.preferredRateSource],
    );

    return _countByNativeStreamCombined(filters: filters).switchMap((stat) {
      return CurrencyConversionHelper.instance
          .convertMixedCurrenciesToTarget(
            byNative: Stream.value(stat.byNative),
            target: targetCurrency,
            source: rateSource,
            date: exchDate,
          )
          .map<double?>((result) => result.convertedTotal);
    });
  }

  /// Internal helper: replicates the transfer-aware predicate fan-out from
  /// [_countTransactions] but emits a single `(count, byNative)` tuple
  /// (instead of a converted [TransactionQueryStatResult]) so callers like
  /// [getTransactionsCountAndBalanceWithMissing] can route the map through
  /// the missing-aware variant of [CurrencyConversionHelper].
  Stream<({int count, Map<String, double> byNative})>
      _countByNativeStreamCombined({
    required TransactionFilterSet filters,
  }) {
    if (filters.transactionTypes == null ||
        filters.transactionTypes!
            .map((e) => e.index)
            .contains(TransactionType.transfer.index)) {
      // Fan out: incomes/expenses (origin), transfers-out (origin),
      // transfers-in (destiny). Subtract the transfers-out side and add
      // the transfers-in side, mirroring [_countTransactions].
      final incomeAndExpense$ = _countByNativeStream(
        filters: filters.copyWith(
          transactionTypes:
              filters.transactionTypes
                  ?.whereNot(
                    (element) =>
                        element.index == TransactionType.transfer.index,
                  )
                  .toList() ??
              [TransactionType.income, TransactionType.expense],
        ),
      );
      final transfersFromOrigin$ = _countByNativeStream(
        filters: filters.copyWith(
          transactionTypes: [TransactionType.transfer],
          includeReceivingAccountsInAccountFilters: false,
        ),
      );
      final transfersFromDestiny$ = _countByNativeStream(
        filters: filters.copyWith(
          transactionTypes: [TransactionType.transfer],
          accountsIDs: null,
        ),
        extraFilters:
            (
              transaction,
              account,
              accountCurrency,
              receivingAccount,
              receivingAccountCurrency,
              c,
              p6,
            ) => [
              if (filters.accountsIDs != null)
                transaction.receivingAccountID.isIn(filters.accountsIDs!),
            ],
      );

      return Rx.combineLatest3(
        incomeAndExpense$,
        transfersFromOrigin$,
        transfersFromDestiny$,
        (incomeRows, txOriginRows, txDestinyRows) {
          var count = 0;
          final map = <String, double>{};
          for (final row in incomeRows) {
            count += row.transactionsNumber;
            map.update(
              row.currencyId,
              (existing) => existing + row.sumNative,
              ifAbsent: () => row.sumNative,
            );
          }
          for (final row in txOriginRows) {
            count += row.transactionsNumber;
            map.update(
              row.currencyId,
              (existing) => existing - row.sumNative,
              ifAbsent: () => -row.sumNative,
            );
          }
          for (final row in txDestinyRows) {
            // transfersFromDestiny rows do NOT contribute to count (they are
            // the destiny-side of the same transfers already counted above).
            map.update(
              row.destinyCurrencyId,
              (existing) => existing + row.sumInDestinyNative,
              ifAbsent: () => row.sumInDestinyNative,
            );
          }
          return (count: count, byNative: map);
        },
      );
    }

    // Single query path (no transfers).
    return _countByNativeStream(filters: filters).map((rows) {
      var count = 0;
      final map = <String, double>{};
      for (final row in rows) {
        count += row.transactionsNumber;
        map.update(
          row.currencyId,
          (existing) => existing + row.sumNative,
          ifAbsent: () => row.sumNative,
        );
      }
      return (count: count, byNative: map);
    });
  }

  /// Per-currency raw row stream from the Drift query (post-Phase-9
  /// reshape). Each emission is the full GROUP BY result set for the
  /// given predicate. Conversion to display currency happens Dart-side
  /// in [_aggregateNativeGroups].
  ///
  /// Phase 9 of `currency-modes-rework` deleted the `:date`,
  /// `:preferredCurrency`, and `:rateSource` parameters from the SQL —
  /// the rate-driven projections are gone, and we sum natively per
  /// `currencyId` group.
  Stream<List<CountTransactionsResult>> _countByNativeStream({
    required TransactionFilterSet filters,
    Iterable<Expression<bool>> Function(
      Transactions,
      Accounts,
      Currencies,
      Accounts,
      Currencies,
      Categories,
      Categories,
    )?
    extraFilters,
  }) {
    return db
        .countTransactions(
          predicate: filters.toTransactionExpression(extraFilters: extraFilters),
        )
        .watch();
  }

  /// Folds the per-currency result rows into a [TransactionQueryStatResult]
  /// envelope. When [convertToPreferredCurrency] is true, the
  /// per-currency native sums are routed through
  /// [CurrencyConversionHelper] to produce a single display-currency
  /// total — non-target portions are converted via
  /// `ExchangeRateService.calculateExchangeRate`, and groups whose rate
  /// is missing are EXCLUDED (no silent `?? 1.0` fallback).
  Stream<TransactionQueryStatResult> _aggregateNativeGroups({
    required Stream<List<CountTransactionsResult>> rowsStream,
    required bool convertToPreferredCurrency,
    required bool useDestinyCurrency,
    DateTime? exchDate,
  }) {
    final String target =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
    final RateSource rateSource = RateSource.fromDb(
      appStateSettings[SettingKey.preferredRateSource],
    );

    if (!convertToPreferredCurrency) {
      // Pure native fold — sum all groups in their own currency.
      return rowsStream.map((rows) {
        var count = 0;
        var nativeTotal = 0.0;
        for (final row in rows) {
          count += row.transactionsNumber;
          nativeTotal += useDestinyCurrency
              ? row.sumInDestinyNative
              : row.sumNative;
        }
        return TransactionQueryStatResult(
          numberOfRes: count,
          valueSum: nativeTotal,
        );
      });
    }

    // Conversion path: project each emission into a `Map<currencyId, sum>`
    // and a count, then fold the converted total back in with the count.
    final byNative$ = rowsStream.map((rows) {
      var count = 0;
      final map = <String, double>{};
      for (final row in rows) {
        count += row.transactionsNumber;
        final currency = useDestinyCurrency
            ? row.destinyCurrencyId
            : row.currencyId;
        final amount = useDestinyCurrency
            ? row.sumInDestinyNative
            : row.sumNative;
        map.update(
          currency,
          (existing) => existing + amount,
          ifAbsent: () => amount,
        );
      }
      return (count: count, map: map);
    });

    return byNative$.switchMap((stat) {
      return CurrencyConversionHelper.instance
          .convertMixedCurrenciesToTotal(
            byNative: Stream.value(stat.map),
            target: target,
            source: rateSource,
            date: exchDate,
          )
          .map(
            (converted) => TransactionQueryStatResult(
              numberOfRes: stat.count,
              valueSum: converted,
            ),
          );
    });
  }

  Stream<TransactionQueryStatResult> _countTransactions({
    TransactionFilterSet predicate = const TransactionFilterSet(),
    bool convertToPreferredCurrency = true,
    DateTime? exchDate,
  }) {
    if (predicate.transactionTypes == null ||
        predicate.transactionTypes!
            .map((e) => e.index)
            .contains(TransactionType.transfer.index)) {
      // If we should take into account transfers, we run THREE queries
      // and combine: incomes/expenses (origin), transfers-out (origin),
      // transfers-in (destiny). Each is fed through `_aggregateNativeGroups`
      // independently so the conversion respects the correct
      // currency-side (origin vs destiny) per group.
      final incomeAndExpense$ = _aggregateNativeGroups(
        rowsStream: _countByNativeStream(
          filters: predicate.copyWith(
            transactionTypes:
                predicate.transactionTypes
                    ?.whereNot(
                      (element) =>
                          element.index == TransactionType.transfer.index,
                    )
                    .toList() ??
                [TransactionType.income, TransactionType.expense],
          ),
        ),
        convertToPreferredCurrency: convertToPreferredCurrency,
        useDestinyCurrency: false,
        exchDate: exchDate,
      );

      final transfersFromOrigin$ = _aggregateNativeGroups(
        rowsStream: _countByNativeStream(
          filters: predicate.copyWith(
            transactionTypes: [TransactionType.transfer],
            includeReceivingAccountsInAccountFilters: false,
          ),
        ),
        convertToPreferredCurrency: convertToPreferredCurrency,
        useDestinyCurrency: false,
        exchDate: exchDate,
      );

      final transfersFromDestiny$ = _aggregateNativeGroups(
        rowsStream: _countByNativeStream(
          filters: predicate.copyWith(
            transactionTypes: [TransactionType.transfer],
            accountsIDs: null,
          ),
          extraFilters:
              (
                transaction,
                account,
                accountCurrency,
                receivingAccount,
                receivingAccountCurrency,
                c,
                p6,
              ) => [
                if (predicate.accountsIDs != null)
                  transaction.receivingAccountID.isIn(predicate.accountsIDs!),
              ],
        ),
        convertToPreferredCurrency: convertToPreferredCurrency,
        useDestinyCurrency: true,
        exchDate: exchDate,
      );

      return Rx.combineLatest3(
        incomeAndExpense$,
        transfersFromOrigin$,
        transfersFromDestiny$,
        (incomeExp, txOrigin, txDestiny) {
          return TransactionQueryStatResult(
            numberOfRes:
                incomeExp.numberOfRes + txOrigin.numberOfRes,
            valueSum:
                incomeExp.valueSum -
                txOrigin.valueSum +
                txDestiny.valueSum,
          );
        },
      );
    }

    // If transfers are excluded, we run a single query.
    return _aggregateNativeGroups(
      rowsStream: _countByNativeStream(filters: predicate),
      convertToPreferredCurrency: convertToPreferredCurrency,
      useDestinyCurrency: false,
      exchDate: exchDate,
    );
  }

  Stream<MoneyTransaction?> getTransactionById(String id) {
    return db
        .getTransactionsWithFullData(
          predicate:
              (
                transaction,
                account,
                accountCurrency,
                receivingAccount,
                receivingAccountCurrency,
                c,
                p6,
              ) => transaction.id.equals(id),
          preferredCurrency:
              appStateSettings[SettingKey.preferredCurrency] ?? 'USD',
          rateSource:
              appStateSettings[SettingKey.preferredRateSource] ?? 'bcv',
          limit: (t, a, accountCurrency, ra, receivingAccountCurrency, c, pc) =>
              Limit(1, 0),
        )
        .watchSingleOrNull();
  }

  Stream<bool> checkIfCreateTransactionIsPossible() {
    return AccountService.instance
        .getAccounts(
          predicate: (acc, curr) => buildDriftExpr([
            acc.type.equalsValue(AccountType.saving).not(),
            acc.closingDate.isNull(),
          ]),
          limit: 1,
        )
        .map((event) => event.isNotEmpty);
  }
}
