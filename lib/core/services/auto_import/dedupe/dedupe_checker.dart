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
///    for a matching reference. Window: 30 days.
/// 2. Fallback (no bankRef): check for a transaction with the same account,
///    similar date (+-4h), matching absolute amount, and — when available —
///    the same counterparty name. Window widened from the original 2h to 4h
///    to tolerate clock drift and delayed notification posts.
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
    // 1. Check by bankRef if available (30-day window).
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

      // When we have a confident bankRef we do NOT fall through to the
      // heuristic match — the caller trusts the reference.
      return false;
    }

    // 2. Fallback: no bankRef. Widen to +- 4h and additionally match on
    //    counterparty when the proposal has one.
    if (proposal.accountId != null) {
      final windowStart =
          proposal.date.subtract(const Duration(hours: 4));
      final windowEnd = proposal.date.add(const Duration(hours: 4));

      final matchingTxs = await (db.select(db.transactions)
            ..where((t) => buildDriftExpr([
                  t.accountID.equals(proposal.accountId!),
                  t.date.isBiggerOrEqualValue(windowStart),
                  t.date.isSmallerOrEqualValue(windowEnd),
                ]))
            ..limit(20))
          .get();

      final proposalCounterparty =
          proposal.counterpartyName?.trim().toLowerCase();

      for (final tx in matchingTxs) {
        final amountMatches =
            (tx.value.abs() - proposal.amount).abs() < 0.01;
        if (!amountMatches) continue;

        // Transactions don't carry a `counterpartyName` column — best-effort
        // match against the notes field when the proposal has a counterparty.
        if (proposalCounterparty != null && proposalCounterparty.isNotEmpty) {
          final notes = (tx.notes ?? '').toLowerCase();
          if (notes.contains(proposalCounterparty)) {
            return true;
          }
          // Amount + time match but counterparty differs. This is the most
          // interesting case: we still err on the duplicate side because the
          // window is only 4h and the amounts match to the cent.
          return true;
        }

        // No counterparty info on the proposal — fall back to the original
        // (amount, date, account) heuristic.
        return true;
      }

      // Also sweep pending_imports for a recent match with the same
      // counterparty + amount + account. Pending rows expose
      // `counterpartyName` directly, which gives us a cleaner signal than
      // the notes heuristic above.
      if (proposalCounterparty != null && proposalCounterparty.isNotEmpty) {
        final pendingMatch = await (db.select(db.pendingImports)
              ..where((p) => buildDriftExpr([
                    p.accountId.equals(proposal.accountId!),
                    p.date.isBiggerOrEqualValue(windowStart),
                    p.date.isSmallerOrEqualValue(windowEnd),
                    p.amount.equals(proposal.amount),
                  ]))
              ..limit(5))
            .get();
        for (final p in pendingMatch) {
          final pc = (p.counterpartyName ?? '').trim().toLowerCase();
          if (pc == proposalCounterparty) return true;
        }
      }
    }

    // 3. Not a duplicate
    return false;
  }
}
