import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:kilatex/core/database/app_db.dart';
import 'package:kilatex/core/database/services/pending_import/pending_import_service.dart';
import 'package:kilatex/core/database/utils/drift_utils.dart';
import 'package:kilatex/core/models/auto_import/transaction_proposal.dart';

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
    // [DEDUPE-DBG] Log incoming proposal essentials.
    debugPrint(
      '[DEDUPE-DBG] check() entry — bankRef=${proposal.bankRef} '
      '(len=${proposal.bankRef?.length ?? 0}, '
      'codeUnits=${proposal.bankRef?.codeUnits.take(40).toList()}) '
      'accountId=${proposal.accountId} amount=${proposal.amount} '
      'currency=${proposal.currencyId} sender=${proposal.sender}',
    );

    // 1. Check by bankRef if available (30-day window).
    if (proposal.bankRef != null && proposal.bankRef!.isNotEmpty) {
      // [DEDUPE-DBG] Pre-query pending_imports scoped by accountId (when present).
      debugPrint(
        '[DEDUPE-DBG] querying pendingImports WHERE bankRef=${proposal.bankRef} '
        '${proposal.accountId != null ? "AND accountId=${proposal.accountId}" : "(no accountId scope)"}',
      );
      // Check pending_imports by bankRef (+ accountId when available) — prevents re-classifying same proposal each poll.
      final pendingByRef = await (db.select(db.pendingImports)
            ..where((p) => proposal.accountId != null
                ? buildDriftExpr([
                    p.bankRef.equals(proposal.bankRef!),
                    p.accountId.equals(proposal.accountId!),
                  ])
                : p.bankRef.equals(proposal.bankRef!))
            ..limit(1))
          .getSingleOrNull();
      debugPrint(
        '[DEDUPE-DBG] pendingByRef result: '
        '${pendingByRef == null ? "NULL (no match)" : "FOUND id=${pendingByRef.id} bankRef=${pendingByRef.bankRef} accountId=${pendingByRef.accountId} status=${pendingByRef.status}"}',
      );
      if (pendingByRef != null) {
        debugPrint('[DEDUPE-DBG] decision=DUPLICATE via pendingByRef (scoped)');
        return true;
      }

      // Legacy path: also defer to the service helper for any non-account-scoped match.
      debugPrint('[DEDUPE-DBG] querying findByBankRef (legacy, no account scope) bankRef=${proposal.bankRef}');
      final existingImport =
          await pendingImportService.findByBankRef(proposal.bankRef!);
      debugPrint(
        '[DEDUPE-DBG] findByBankRef result: '
        '${existingImport == null ? "NULL (no match)" : "FOUND id=${existingImport.id} bankRef=${existingImport.bankRef} accountId=${existingImport.accountId} status=${existingImport.status}"}',
      );
      if (existingImport != null) {
        debugPrint('[DEDUPE-DBG] decision=DUPLICATE via findByBankRef (legacy)');
        return true;
      }

      // Check transactions table for bankRef in notes
      final refPattern = 'ref=${proposal.bankRef}';
      final txByRef = await (db.select(db.transactions)
            ..where((t) => t.notes.contains(refPattern))
            ..limit(1))
          .getSingleOrNull();
      debugPrint(
        '[DEDUPE-DBG] txByRef("$refPattern") result: '
        '${txByRef == null ? "NULL" : "FOUND id=${txByRef.id}"}',
      );
      if (txByRef != null) {
        debugPrint('[DEDUPE-DBG] decision=DUPLICATE via txByRef notes');
        return true;
      }

      // 1b. Manual-tx fallback for binance proposals: when a user manually
      //     registered a transaction in the app, the bankRef pattern
      //     `ref=...` is never written into transactions.notes, so the
      //     check above always misses. As a result Binance polling keeps
      //     re-reporting the same transactions every few minutes. Match
      //     against the same account, an exact monetary amount (within 1
      //     cent) and a 24h date window — but ONLY for binance-sourced
      //     proposals so the fallback can't false-positive on unrelated
      //     transactions.
      final manualMatch = await _matchesManualBinanceTx(proposal);
      debugPrint('[DEDUPE-DBG] _matchesManualBinanceTx => $manualMatch');
      if (manualMatch) {
        debugPrint('[DEDUPE-DBG] decision=DUPLICATE via manual binance match');
        return true;
      }

      // When we have a confident bankRef we do NOT fall through to the
      // heuristic match — the caller trusts the reference.
      debugPrint(
        '[DEDUPE-DBG] decision=NOT_DUPLICATE — bankRef path exhausted, '
        'returning false (insert will be attempted) bankRef=${proposal.bankRef}',
      );
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

  /// Detects a manually-registered transaction that mirrors an incoming
  /// binance proposal. Binance API events carry a `bankRef` (so the normal
  /// bankRef path runs), but when the user already entered the same
  /// transaction by hand the `transactions` table has no `ref=...` marker,
  /// so the bankRef path misses. This helper closes that gap.
  ///
  /// Defensive guards:
  /// - skip when the proposal is NOT binance-sourced (avoid false positives);
  /// - skip when `accountId` hasn't been resolved.
  Future<bool> _matchesManualBinanceTx(TransactionProposal proposal) async {
    final sender = proposal.sender?.toLowerCase() ?? '';
    if (!sender.startsWith('binance:')) return false;

    if (proposal.accountId == null) return false;

    final windowStart =
        proposal.date.subtract(const Duration(hours: 24));
    final windowEnd = proposal.date.add(const Duration(hours: 24));

    final candidates = await (db.select(db.transactions)
          ..where((t) => buildDriftExpr([
                t.accountID.equals(proposal.accountId!),
                t.date.isBiggerOrEqualValue(windowStart),
                t.date.isSmallerOrEqualValue(windowEnd),
              ]))
          ..limit(20))
        .get();

    for (final tx in candidates) {
      final amountMatches =
          (tx.value.abs() - proposal.amount).abs() < 0.01;
      if (amountMatches) return true;
    }

    return false;
  }
}
