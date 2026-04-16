import 'package:drift/drift.dart';
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
  Future<int> insertPendingImport(PendingImportsCompanion companion) {
    return db.into(db.pendingImports).insert(companion);
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
  Future<PendingImportInDB?> findByBankRef(String bankRef) {
    final query = db.select(db.pendingImports)
      ..where((t) => t.bankRef.equals(bankRef))
      ..limit(1);

    return query.getSingleOrNull();
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
