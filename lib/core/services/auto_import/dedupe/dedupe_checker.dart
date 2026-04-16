import 'package:drift/drift.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/database/utils/drift_utils.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';

/// Checks whether a [TransactionProposal] is a duplicate of an existing
/// transaction or pending import.
///
/// Deduplication strategy:
/// 1. If the proposal has a `bankRef`, check `pending_imports` and `transactions`
///    for a matching reference.
/// 2. Fallback: check for a transaction with the same account, similar date (+-2h),
///    and matching absolute amount.
class DedupeChecker {
  final AppDB db;
  final PendingImportService pendingImportService;

  DedupeChecker._({
    required this.db,
    required this.pendingImportService,
  });

  static final DedupeChecker instance = DedupeChecker._(
    db: AppDB.instance,
    pendingImportService: PendingImportService.instance,
  );

  /// For testing: create an instance with a custom [AppDB] and [PendingImportService].
  DedupeChecker.forTesting({
    required this.db,
    required this.pendingImportService,
  });

  /// Returns `true` if the proposal is a duplicate.
  Future<bool> check(TransactionProposal proposal) async {
    // 1. Check by bankRef if available
    if (proposal.bankRef != null && proposal.bankRef!.isNotEmpty) {
      // Check pending_imports table
      final existingImport =
          await pendingImportService.findByBankRef(proposal.bankRef!);
      if (existingImport != null) return true;

      // Check transactions table for bankRef in notes
      final refPattern = 'ref=${proposal.bankRef}';
      final txByRef = await (db.select(db.transactions)
            ..where((t) => t.notes.contains(refPattern))
            ..limit(1))
          .getSingleOrNull();
      if (txByRef != null) return true;
    }

    // 2. Fallback: check by (accountId, date +- 2h, ABS(value) == amount)
    if (proposal.accountId != null) {
      final windowStart =
          proposal.date.subtract(const Duration(hours: 2));
      final windowEnd = proposal.date.add(const Duration(hours: 2));

      final matchingTxs = await (db.select(db.transactions)
            ..where((t) => buildDriftExpr([
                  t.accountID.equals(proposal.accountId!),
                  t.date.isBiggerOrEqualValue(windowStart),
                  t.date.isSmallerOrEqualValue(windowEnd),
                ]))
            ..limit(10))
          .get();

      for (final tx in matchingTxs) {
        if ((tx.value.abs() - proposal.amount).abs() < 0.01) {
          return true;
        }
      }
    }

    // 3. Not a duplicate
    return false;
  }
}
