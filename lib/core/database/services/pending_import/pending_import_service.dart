import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal_status.dart';

/// CRUD service for the `pending_imports` table.
///
/// Follows the same singleton + AppDB pattern as [TransactionService].
class PendingImportService {
  final AppDB db;

  PendingImportService._(this.db);

  static final PendingImportService instance = PendingImportService._(
    AppDB.instance,
  );

  /// For testing: create an instance with a custom [AppDB].
  PendingImportService.forTesting(this.db);

  /// Insert a new pending import row. Returns the auto-generated rowid.
  Future<int> insertPendingImport(PendingImportsCompanion companion) async {
    final bankRefVal = companion.bankRef.present ? companion.bankRef.value : '<absent>';
    final idVal = companion.id.present ? companion.id.value : '<absent>';
    final accountIdVal =
        companion.accountId.present ? companion.accountId.value : '<absent>';
    debugPrint(
      '[DEDUPE-DBG] PendingImportService.insertPendingImport BEGIN '
      'id=$idVal bankRef=$bankRefVal accountId=$accountIdVal',
    );
    try {
      final rowId = await db.into(db.pendingImports).insert(companion);
      debugPrint(
        '[DEDUPE-DBG] PendingImportService.insertPendingImport SUCCESS '
        'rowId=$rowId id=$idVal bankRef=$bankRefVal',
      );
      return rowId;
    } catch (e, st) {
      debugPrint(
        '[DEDUPE-DBG] PendingImportService.insertPendingImport THREW '
        'id=$idVal bankRef=$bankRefVal error=$e\n$st',
      );
      rethrow;
    }
  }

  /// Watch all pending imports, optionally filtered by [status].
  ///
  /// Results are ordered by `createdAt DESC` (newest first).
  Stream<List<PendingImportInDB>> getPendingImports({
    TransactionProposalStatus? status,
  }) {
    final query = db.select(db.pendingImports)
      ..orderBy([
        (t) => OrderingTerm(
              expression: t.createdAt,
              mode: OrderingMode.desc,
            ),
      ]);

    if (status != null) {
      query.where((t) => t.status.equals(status.dbValue));
    }

    return query.watch();
  }

  /// Atomically update the status of a pending import.
  ///
  /// If [createdTransactionId] is provided (typically when confirming),
  /// it is persisted alongside the status update.
  Future<int> updatePendingImportStatus(
    String id,
    TransactionProposalStatus newStatus, {
    String? createdTransactionId,
  }) {
    return (db.update(db.pendingImports)
          ..where((t) => t.id.equals(id)))
        .write(
      PendingImportsCompanion(
        status: Value(newStatus.dbValue),
        createdTransactionId: createdTransactionId != null
            ? Value(createdTransactionId)
            : const Value.absent(),
      ),
    );
  }

  /// Reactive stream of the count of pending imports with status 'pending'.
  ///
  /// Useful for the badge on the bottom navigation bar.
  Stream<int> watchPendingCount() {
    final countExpr = db.pendingImports.id.count();

    final query = db.selectOnly(db.pendingImports)
      ..addColumns([countExpr])
      ..where(
        db.pendingImports.status.equals(TransactionProposalStatus.pending.dbValue),
      );

    return query.map((row) => row.read(countExpr)!).watchSingle();
  }

  /// Find a pending import by its bank reference number.
  ///
  /// Used for cross-channel deduplication (e.g. same BDV event arriving
  /// via both SMS and push notification).
  Future<PendingImportInDB?> findByBankRef(String bankRef) async {
    debugPrint(
      '[DEDUPE-DBG] PendingImportService.findByBankRef '
      'bankRef="$bankRef" (len=${bankRef.length}, '
      'codeUnits=${bankRef.codeUnits.take(40).toList()})',
    );
    final query = db.select(db.pendingImports)
      ..where((t) => t.bankRef.equals(bankRef))
      ..limit(1);

    final result = await query.getSingleOrNull();
    debugPrint(
      '[DEDUPE-DBG] PendingImportService.findByBankRef result: '
      '${result == null ? "NULL" : "FOUND id=${result.id} bankRef=\"${result.bankRef}\" status=${result.status}"}',
    );
    return result;
  }

  /// Delete rejected pending imports older than [olderThan].
  ///
  /// Housekeeping method — not called in Tanda 1 but defined for future use.
  Future<int> deleteOldRejected({
    Duration olderThan = const Duration(days: 30),
  }) {
    final cutoff = DateTime.now().subtract(olderThan);

    return (db.delete(db.pendingImports)
          ..where(
            (t) =>
                t.status.equals(TransactionProposalStatus.rejected.dbValue) &
                t.createdAt.isSmallerThanValue(cutoff),
          ))
        .go();
  }
}
