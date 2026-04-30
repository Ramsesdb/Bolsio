import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/extensions/numbers.extensions.dart';
import 'package:bolsio/core/models/account/account.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:rxdart/rxdart.dart';

import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/services/firebase_sync_service.dart';

enum AccountDataFilter { income, expense, balance }

class AccountService {
  final AppDB db;

  AccountService._(this.db);
  static final AccountService instance = AccountService._(AppDB.instance);

  Future<int> insertAccount(AccountInDB account) async {
    final toReturn = await db.into(db.accounts).insert(account);
    unawaited(FirebaseSyncService.instance.pushAccount(account));
    return toReturn;
  }

  Future<bool> updateAccount(AccountInDB account) async {
    final toReturn = await db.update(db.accounts).replace(account);
    unawaited(FirebaseSyncService.instance.pushAccount(account));
    return toReturn;
  }

  Future<int> deleteAccount(String accountId) async {
    final toReturn = await (db.delete(
      db.accounts,
    )..where((tbl) => tbl.id.equals(accountId))).go();
    unawaited(FirebaseSyncService.instance.deleteAccount(accountId));
    return toReturn;
  }

  Stream<List<Account>> getAccounts({
    Expression<bool> Function(Accounts acc, Currencies curr)? predicate,
    OrderBy Function(Accounts acc, Currencies curr)? orderBy,
    int? limit,
    int? offset,
  }) {
    return db
        .getAccountsWithFullData(
          predicate: predicate,
          orderBy:
              orderBy ??
              (acc, curr) => OrderBy([OrderingTerm.asc(acc.displayOrder)]),
          limit: (a, currency) => Limit(limit ?? -1, offset),
        )
        .watch();
  }

  Stream<Account?> getAccountById(String id) {
    return getAccounts(
      predicate: (a, c) => a.id.equals(id),
      limit: 1,
    ).map((res) => res.firstOrNull);
  }

  /// Build a CTE + JOIN pair that exposes the latest exchange rate per
  /// currency, preferring the [rateSource] when multiple rates share the same
  /// date. Replaces the legacy triple-nested correlated subquery (O(n×m))
  /// with a single pass over `exchangeRates` using `ROW_NUMBER()` (O(n+m)).
  ///
  /// The returned [withClause] must be prepended to the full SQL **once**,
  /// before `SELECT`. The [joinClause] uses a plain `LEFT JOIN latestRates …`.
  ///
  /// Parameter ordering (CRITICAL): `?` placeholders bind in textual order
  /// across the final SQL string, so callers MUST put the CTE variables at
  /// the very start of their `variables:` list — `rateSource` first, then
  /// `date` if provided.
  ({String withClause, String joinClause}) _latestRatesCte({
    required DateTime? date,
    String columnName = 'excRate',
  }) {
    final withClause =
        '''
    WITH latestRates AS (
      SELECT currencyCode, exchangeRate FROM (
        SELECT
          er.currencyCode,
          er.exchangeRate,
          ROW_NUMBER() OVER (
            PARTITION BY er.currencyCode
            ORDER BY er.date DESC,
              CASE WHEN er.source = ? THEN 0 ELSE 1 END,
              er.id
          ) AS rn
        FROM exchangeRates er
        ${date != null ? 'WHERE unixepoch(er.date) <= unixepoch(?)' : ''}
      ) WHERE rn = 1
    )
    ''';

    final joinClause =
        '''
    LEFT JOIN latestRates AS $columnName ON accounts.currencyId = $columnName.currencyCode
    ''';

    return (withClause: withClause, joinClause: joinClause);
  }

  /// Get the amount of money that an account has in a certain period of time,
  /// specified in the [date] param. If the [date] param is null, it will return
  /// the money of the account right now.
  ///
  /// You can add filters for the transactions that will be taken into account to calculate
  /// this balance, via the [trFilters] param.
  ///
  /// By default, the returned amount will be in the account currency.
  ///
  /// Example:
  ///
  /// ```dart
  /// final account = Account(/*....*/)
  ///
  /// final moneyStream = getAccountMoney(
  ///   account: account,
  ///   date: DateTime.now(),
  ///   convertToPreferredCurrency: true,
  /// );
  ///
  /// moneyStream.listen((money) {
  ///   Logger.printDebug('Money: \$\${money.toStringAsFixed(2)}');
  /// });
  /// ```
  Stream<double> getAccountMoney({
    required Account account,
    DateTime? date,
    TransactionFilterSet trFilters = const TransactionFilterSet(),
    bool convertToPreferredCurrency = false,
  }) {
    return getAccountsMoney(
      accountIds: [account.id],
      date: date,
      trFilters: trFilters,
      convertToPreferredCurrency: convertToPreferredCurrency,
    ).map((result) => result.roundWithDecimals(account.currency.decimalPlaces));
  }

  /// Get the amount of money that some accounts have in a certain period of time,
  /// specified in the [date] param. If the [date] param is null, it will return
  /// the money of the account right now.
  ///
  /// If the [accountIds] param is not specified, the function will return the money of
  /// all the user accounts (closed or not).
  ///
  /// You can add filters for the transactions that will be taken into account to calculate
  /// this balance, via the [trFilters] param. We will overwrite the accountsIds and the maxDate
  /// param of this filter, based on the other params in this func.
  Stream<double> getAccountsMoney({
    Iterable<String>? accountIds,
    DateTime? date,
    TransactionFilterSet trFilters = const TransactionFilterSet(),
    bool convertToPreferredCurrency = true,
  }) {
    final useDate = date ?? DateTime.now();
    final preferredCurrency =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
    final rateSource =
        appStateSettings[SettingKey.preferredRateSource] ?? 'bcv';

    // Build the latest-rates CTE once; its `?` placeholders bind in textual
    // order so they MUST come first in the `variables:` list below.
    final cte = convertToPreferredCurrency
        ? _latestRatesCte(date: date)
        : null;

    // Get the accounts initial balance (converted to the preferred currency if necessary)
    final initialBalanceQuery = db
        .customSelect(
          """
          ${cte?.withClause ?? ''}
          SELECT COALESCE(
            SUM(
              CASE WHEN accounts.date > ? THEN 0
              ELSE accounts.iniValue
                ${convertToPreferredCurrency ? ' * CASE WHEN accounts.currencyId = ? THEN 1.0 ELSE excRate.exchangeRate END' : ''}
              END
            )
          , 0)
          AS balance
          FROM accounts
              ${cte?.joinClause ?? ''}
              ${accountIds != null ? 'WHERE accounts.id IN (${List.filled(accountIds.length, '?').join(', ')})' : ''}
          """,
          readsFrom: {
            db.accounts,
            db.transactions, // Force re-emit when transactions change
            if (convertToPreferredCurrency) db.exchangeRates,
          },
          variables: [
            // CTE parameters MUST come first (textual order of `?` in SQL):
            //   1. rateSource            → `CASE WHEN er.source = ?`
            //   2. useDate (only when date != null) → `unixepoch(er.date) <= unixepoch(?)`
            if (convertToPreferredCurrency)
              Variable.withString(rateSource),
            if (convertToPreferredCurrency && date != null)
              Variable.withDateTime(useDate),
            // Main query parameters:
            Variable.withDateTime(useDate),
            if (convertToPreferredCurrency)
              Variable.withString(preferredCurrency),
            if (accountIds != null)
              for (final id in accountIds) Variable.withString(id),
          ],
        )
        .watch()
        .map((rows) {
          if (rows.isNotEmpty && rows.first.data['balance'] != null) {
            return (rows.first.data['balance'] as num).roundWithDecimals(8);
          }
          return 0.0;
        });

    // Sum the acount initial balance and the balance of the transactions
    return Rx.combineLatest2(
      initialBalanceQuery.map((val) {
        // Logger.printDebug('AccountService: Initial balance emitted: $val');
        return val;
      }),
      TransactionService.instance
          .getTransactionsValueBalance(
            filters: trFilters.copyWith(
              maxDate: useDate,
              accountsIDs: accountIds,
              // Exclude pre-tracking transactions from the current balance.
              // See account.trackedSince / `account-pre-tracking-period`.
              respectTrackedSince: true,
            ),
            convertToPreferredCurrency: convertToPreferredCurrency,
          )
          .map((val) {
            // Logger.printDebug('AccountService: Tx balance emitted: $val');
            return val;
          }),
      (double initial, double tx) {
        // Logger.printDebug('AccountService: Combined balance: ${initial + tx}');
        return initial + tx;
      },
    );
  }

  /// Returns a stream of a double, representing the variation in money for a list of accounts between two dates.
  ///
  /// If the user does not provide a value for endDate, the function sets it to the
  /// current date. If the user does not provide a value for startDate, the function
  /// sets it to the minimum date in the list of accounts.
  ///
  /// You can add filters for the transactions that will be taken into account to calculate
  /// this value, via the [trFilters] param. We will overwrite the accountsIds
  /// param of this filter, based on the param in this func.
  Stream<double> getAccountsMoneyVariation({
    required List<Account> accounts,
    DateTime? startDate,
    DateTime? endDate,
    TransactionFilterSet trFilters = const TransactionFilterSet(),
    bool convertToPreferredCurrency = true,
  }) {
    if (accounts.isEmpty) return Stream.value(0);

    endDate ??= DateTime.now();
    startDate ??= accounts.map((e) => e.date).min;

    final Iterable<String> accountIds = accounts.map((e) => e.id);

    final overwrittenFilters = trFilters.copyWith(
      accountsIDs: accountIds.toList(),
    );

    final accountsBalanceStartPeriod = getAccountsMoney(
      accountIds: accountIds,
      date: startDate,
      trFilters: overwrittenFilters,
      convertToPreferredCurrency: convertToPreferredCurrency,
    );

    final accountsBalanceDuringPeriod = TransactionService.instance
        .getTransactionsValueBalance(
          filters: overwrittenFilters.copyWith(
            minDate: startDate,
            maxDate: endDate,
          ),
          convertToPreferredCurrency: convertToPreferredCurrency,
        );

    return Rx.combineLatest(
      [accountsBalanceStartPeriod, accountsBalanceDuringPeriod],
      (res) {
        final startBalance = res[0];
        final finalBalance = res[1] + startBalance;

        return (finalBalance - startBalance) / startBalance;
      },
    );
  }

  /// Preview-only variant of [getAccountsMoney] that simulates what the
  /// balance of a single account would look like if its `trackedSince`
  /// column had the value [simulatedTrackedSince], **without persisting**
  /// that change in the database.
  ///
  /// Implementation detail: because we are previewing a single account, the
  /// pre-tracking filter is equivalent to forcing `transactions.date >=
  /// simulatedTrackedSince` on the sub-queries (origin + both transfer
  /// legs). We bypass `respectTrackedSince` (which reads the real DB column)
  /// and feed the simulated date as `minDate` of the filter set. When
  /// [simulatedTrackedSince] is null, behaviour is equivalent to not
  /// filtering that account for tracking (full historical balance).
  Stream<double> getAccountsMoneyPreview({
    required String accountId,
    required DateTime? simulatedTrackedSince,
    bool convertToPreferredCurrency = true,
  }) {
    final useDate = DateTime.now();
    final preferredCurrency =
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
    final rateSource =
        appStateSettings[SettingKey.preferredRateSource] ?? 'bcv';

    // No date cutoff for the preview, so the CTE only binds `rateSource`.
    final cte = convertToPreferredCurrency
        ? _latestRatesCte(date: null)
        : null;

    // Mirror of [getAccountsMoney]'s initial-balance query, restricted to
    // the single account being previewed.
    final initialBalanceQuery = db
        .customSelect(
          '''
          ${cte?.withClause ?? ''}
          SELECT COALESCE(
            SUM(
              CASE WHEN accounts.date > ? THEN 0
              ELSE accounts.iniValue
                ${convertToPreferredCurrency ? ' * CASE WHEN accounts.currencyId = ? THEN 1.0 ELSE excRate.exchangeRate END' : ''}
              END
            )
          , 0)
          AS balance
          FROM accounts
              ${cte?.joinClause ?? ''}
              WHERE accounts.id = ?
          ''',
          readsFrom: {
            db.accounts,
            db.transactions,
            if (convertToPreferredCurrency) db.exchangeRates,
          },
          variables: [
            // CTE parameters MUST come first (textual order of `?` in SQL):
            //   1. rateSource → `CASE WHEN er.source = ?`
            //   (no date cutoff in preview, so no second CTE binding)
            if (convertToPreferredCurrency)
              Variable.withString(rateSource),
            // Main query parameters:
            Variable.withDateTime(useDate),
            if (convertToPreferredCurrency)
              Variable.withString(preferredCurrency),
            Variable.withString(accountId),
          ],
        )
        .watch()
        .map((rows) {
          if (rows.isNotEmpty && rows.first.data['balance'] != null) {
            return (rows.first.data['balance'] as num).roundWithDecimals(8);
          }
          return 0.0;
        });

    // Transactions affecting this account, optionally constrained by the
    // simulated tracking start date. `respectTrackedSince` is explicitly
    // false so the real DB column is ignored for this preview.
    final txBalance = TransactionService.instance.getTransactionsValueBalance(
      filters: TransactionFilterSet(
        accountsIDs: [accountId],
        maxDate: useDate,
        minDate: simulatedTrackedSince,
      ),
      convertToPreferredCurrency: convertToPreferredCurrency,
    );

    return Rx.combineLatest2(
      initialBalanceQuery,
      txBalance,
      (double initial, double tx) => initial + tx,
    );
  }
}
