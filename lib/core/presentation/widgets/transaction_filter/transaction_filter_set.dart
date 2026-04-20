import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:drift/drift.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/utils/drift_utils.dart';
import 'package:wallex/core/extensions/string.extension.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/utils/uuid.dart';

import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';

import '../../../models/transaction/transaction_type.enum.dart';

part 'transaction_filter_set.g.dart';

@CopyWith()
/// A set of filters to apply to transactions queries
class TransactionFilterSet {
  /// Accounts that this filter contains. Will be null if this filter is not in use, or if all accounts are selected
  final Iterable<String>? accountsIDs;

  /// Accounts whose transactions should be excluded from the results. Unlike
  /// [accountsIDs] this filter applies with AND semantics to **both sides** of
  /// a transfer: a transaction is discarded if either its origin account or
  /// its receiving account appears in this set. Used by Hidden Mode to hide
  /// every transaction/transfer that touches a saving account while the app
  /// is locked.
  final Iterable<String>? excludeAccountsIDs;

  final bool includeReceivingAccountsInAccountFilters;

  /// Categories that this filter contains. Will be null if this filter is not in use, or if all categories are selected
  final Iterable<String>? categoriesIds;

  /// If we specify a categories filter, return the transactions within a subcategory which parent is on the list
  ///
  /// Defaults to `false`
  final bool includeParentCategoriesInSearch;

  final List<TransactionStatus?>? status;

  final DateTime? minDate;
  final DateTime? maxDate;

  final String? searchValue;

  final List<TransactionType>? transactionTypes;
  final bool? isRecurrent;

  final double? minValue;
  final double? maxValue;

  final Iterable<String?>? tagsIDs;

  /// Filter transactions that belong to a specific debt
  final String? debtId;

  /// Exclude transactions that belong to a specific debt (useful when linking new transactions)
  final String? excludeDebtId;

  /// Runtime-only flag: when true, the predicate builder excludes transactions
  /// with `date < account.trackedSince` (and the symmetric check for the
  /// receiving account of transfers). Used by balance calculations to honour
  /// the account pre-tracking period. Stats/reporting queries keep this as
  /// false so that historical data remains visible in aggregates.
  ///
  /// Not persisted: intentionally excluded from [fromDB]/[toDBModel].
  final bool respectTrackedSince;

  const TransactionFilterSet({
    this.minDate,
    this.maxDate,
    this.searchValue,
    this.includeParentCategoriesInSearch = false,
    this.includeReceivingAccountsInAccountFilters = true,
    this.minValue,
    this.maxValue,
    this.transactionTypes,
    this.isRecurrent,
    this.accountsIDs,
    this.excludeAccountsIDs,
    this.categoriesIds,
    this.status,
    this.tagsIDs,
    this.debtId,
    this.excludeDebtId,
    this.respectTrackedSince = false,
  });

  /// Factory constructor to create a [TransactionFilterSet] from a [TransactionFilterSetInDB]
  factory TransactionFilterSet.fromDB(TransactionFilterSetInDB dbModel) {
    return TransactionFilterSet(
      minDate: dbModel.minDate,
      maxDate: dbModel.maxDate,
      searchValue: dbModel.searchValue,
      minValue: dbModel.minValue,
      maxValue: dbModel.maxValue,
      transactionTypes: dbModel.transactionTypes,
      accountsIDs: dbModel.accountsIDs,
      categoriesIds: dbModel.categoriesIds,
      status: dbModel.status,
      tagsIDs: dbModel.tagsIDs,
    );
  }

  TransactionFilterSetInDB toDBModel({String? id}) {
    return TransactionFilterSetInDB(
      id: id ?? generateUUID(),
      minDate: minDate,
      maxDate: maxDate,
      searchValue: searchValue,
      minValue: minValue,
      maxValue: maxValue,
      transactionTypes: transactionTypes,
      accountsIDs: accountsIDs?.toList(),
      categoriesIds: categoriesIds?.toList(),
      status: status,
      tagsIDs: tagsIDs?.toList(),
    );
  }

  bool get hasFilter => [
    minDate,
    maxDate,
    searchValue?.trim().nullIfEmpty(),
    minValue,
    maxValue,
    transactionTypes,
    isRecurrent,
    accountsIDs,
    // excludeAccountsIDs is deliberately omitted here: it's an internal filter
    // driven by Hidden Mode, not a user-visible one. Counting it would light
    // up the FilterRowIndicator chip even though the user never chose it.
    categoriesIds,
    status,
    tagsIDs,
    debtId,
    excludeDebtId,
  ].any((element) => element != null);

  Stream<List<Account>> accounts() => accountsIDs != null
      ? AccountService.instance.getAccounts(
          predicate: (acc, curr) => acc.id.isIn(accountsIDs!),
        )
      : AccountService.instance.getAccounts();

  Expression<bool> Function(
    Transactions transaction,
    Accounts account,
    Currencies accountCurrency,
    Accounts receivingAccount,
    Currencies receivingAccountCurrency,
    Categories c,
    Categories,
  )?
  toTransactionExpression({
    Iterable<Expression<bool>> Function(
      Transactions transaction,
      Accounts account,
      Currencies accountCurrency,
      Accounts receivingAccount,
      Currencies receivingAccountCurrency,
      Categories c,
      Categories,
    )?
    extraFilters,
  }) {
    return (
      transaction,
      account,
      accountCurrency,
      receivingAccount,
      receivingAccountCurrency,
      c,
      p6,
    ) {
      final preferredCurrency =
          appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

      return buildDriftExpr([
      if (tagsIDs != null)
        CustomExpression(
          "t.id IN (SELECT transactionID FROM transactionTags WHERE tagID IN (${tagsIDs!.where((element) => element != null).map((s) => "'$s'").join(', ')})) ${tagsIDs!.any((element) => element == null) ? 'OR t.id NOT IN (SELECT transactionID FROM transactionTags)' : ''}",
        ),

      if (maxValue != null)
        CustomExpression(
          '(ABS(t.value * CASE WHEN a.currencyId = \'$preferredCurrency\' THEN 1.0 ELSE COALESCE(excRate.exchangeRate, t.exchangeRateApplied) END) <= $maxValue)',
        ),

      if (minValue != null)
        CustomExpression(
          '(ABS(t.value * CASE WHEN a.currencyId = \'$preferredCurrency\' THEN 1.0 ELSE COALESCE(excRate.exchangeRate, t.exchangeRateApplied) END) >= $minValue)',
        ),

      // Transaction types:
      if (transactionTypes != null)
        transaction.type.isInValues(transactionTypes!),

      // Is recurrent:
      if (isRecurrent == false) transaction.intervalPeriod.isNull(),
      if (isRecurrent == true) transaction.intervalPeriod.isNotNull(),

      // Other filters:
      if (searchValue != null && searchValue!.isNotEmpty)
        (transaction.notes.contains(searchValue!) |
            transaction.title.contains(searchValue!) |
            c.name.contains(searchValue!)),
      if (minDate != null) transaction.date.isBiggerOrEqualValue(minDate!),
      if (maxDate != null) transaction.date.isSmallerThanValue(maxDate!),
      if (accountsIDs != null && !includeReceivingAccountsInAccountFilters)
        transaction.accountID.isIn(accountsIDs!),
      if (accountsIDs != null && includeReceivingAccountsInAccountFilters)
        transaction.accountID.isIn(accountsIDs!) |
            transaction.receivingAccountID.isIn(accountsIDs!),
      // Exclude transactions that touch any account in [excludeAccountsIDs].
      // For transfers this must gate **both** sides (AND), otherwise a
      // transfer from a visible account into a hidden saving would leak. A
      // normal transaction has receivingAccountID = NULL, so the right-hand
      // side short-circuits to true and only accountID is checked.
      if (excludeAccountsIDs != null && excludeAccountsIDs!.isNotEmpty)
        transaction.accountID.isIn(excludeAccountsIDs!).not() &
            (transaction.receivingAccountID.isNull() |
                transaction.receivingAccountID
                    .isIn(excludeAccountsIDs!)
                    .not()),
      if (categoriesIds != null && includeParentCategoriesInSearch)
        transaction.categoryID.isIn(categoriesIds!) |
            c.parentCategoryID.isIn(categoriesIds!),
      if (categoriesIds != null && !includeParentCategoriesInSearch)
        transaction.categoryID.isIn(categoriesIds!),
      // Status filter. Defensive against NULL status rows: SQL `IN (...)`
      // never matches NULL, so if the caller explicitly passed `null` inside
      // the list (representing the "no status" bucket) we also include rows
      // where status IS NULL. This protects us from edge cases where a
      // transaction slips through without a status being assigned (see v26
      // backfill migration and the proposal_review / import_csv fixes).
      if (status != null)
        () {
          final nonNullStatuses = status!.whereType<TransactionStatus>().toList();
          final includeNull = status!.any((s) => s == null);
          if (nonNullStatuses.isEmpty && includeNull) {
            return transaction.status.isNull();
          }
          if (includeNull) {
            return transaction.status.isInValues(nonNullStatuses) |
                transaction.status.isNull();
          }
          return transaction.status.isInValues(nonNullStatuses);
        }(),
      if (debtId != null) transaction.debtId.equals(debtId!),
      if (excludeDebtId != null)
        (transaction.debtId.isNull() |
            transaction.debtId.equals(excludeDebtId!).not()),
      // Pre-tracking period: when enabled, exclude transactions whose date
      // falls before the origin account's `trackedSince`. For transfers, the
      // receiving account (`ra`, LEFT JOIN) may be NULL — the left side of
      // the OR handles that case. The symmetric check on the receiving
      // account guarantees that a transfer crossing the frontier on only one
      // side is ignored on both legs, avoiding asymmetrical balance drift.
      if (respectTrackedSince) ...[
        (account.trackedSince.isNull() |
            transaction.date.isBiggerOrEqual(account.trackedSince)),
        (receivingAccount.id.isNull() |
            receivingAccount.trackedSince.isNull() |
            transaction.date.isBiggerOrEqual(receivingAccount.trackedSince)),
      ],
      if (extraFilters != null)
        buildDriftExpr(
          extraFilters(
            transaction,
            account,
            accountCurrency,
            receivingAccount,
            receivingAccountCurrency,
            c,
            p6,
          ).toList(),
        ),
    ]);
    };
  }

  @override
  String toString() {
    return 'TransactionFilterSet(accountsIDs: $accountsIDs, excludeAccountsIDs: $excludeAccountsIDs, categoriesIds: $categoriesIds, includeParentCategoriesInSearch: $includeParentCategoriesInSearch, status: $status, minDate: $minDate, maxDate: $maxDate, searchValue: $searchValue, transactionTypes: $transactionTypes, isRecurrent: $isRecurrent, minValue: $minValue, maxValue: $maxValue, tagsIDs: $tagsIDs, respectTrackedSince: $respectTrackedSince)';
  }
}
