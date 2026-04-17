import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/extensions/numbers.extensions.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:rxdart/rxdart.dart';

import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/firebase_sync_service.dart';

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

  Future<int> deleteAccount(String accountId) {
    return (db.delete(
      db.accounts,
    )..where((tbl) => tbl.id.equals(accountId))).go();
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

  String _joinAccountAndRate(DateTime? date, {String columnName = 'excRate', String? rateSource}) =>
      '''
    LEFT JOIN
      (
          SELECT e1.currencyCode,
                 e1.exchangeRate
            FROM exchangeRates e1
            WHERE e1.id = (
              SELECT e2.id FROM exchangeRates e2
              WHERE e2.currencyCode = e1.currencyCode
                AND e2.date = (
                  SELECT MAX(e3.date) FROM exchangeRates e3
                  WHERE e3.currencyCode = e1.currencyCode
                  ${date != null ? 'AND e3.date <= ?' : ''}
                )
              ORDER BY CASE WHEN e2.source = ? THEN 0 ELSE 1 END
              LIMIT 1
            )
      )
      AS $columnName ON accounts.currencyId = $columnName.currencyCode
    ''';

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

    // Get the accounts initial balance (converted to the preferred currency if necessary)
    final initialBalanceQuery = db
        .customSelect(
          """
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
              ${convertToPreferredCurrency ? _joinAccountAndRate(date, rateSource: rateSource) : ''}
              ${accountIds != null ? 'WHERE accounts.id IN (${List.filled(accountIds.length, '?').join(', ')})' : ''}
          """,
          readsFrom: {
            db.accounts,
            db.transactions, // Force re-emit when transactions change
            if (convertToPreferredCurrency) db.exchangeRates,
          },
          variables: [
            Variable.withDateTime(useDate),
            if (convertToPreferredCurrency)
              Variable.withString(preferredCurrency),
            if (convertToPreferredCurrency && date != null)
              Variable.withDateTime(useDate),
            if (convertToPreferredCurrency)
              Variable.withString(rateSource),
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
}
