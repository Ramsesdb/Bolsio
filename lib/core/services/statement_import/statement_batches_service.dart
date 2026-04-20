import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/services/firebase_sync_service.dart';
import 'package:wallex/core/utils/uuid.dart';

class StatementBatchesService {
  StatementBatchesService({AppDB? database})
      : _db = database ?? AppDB.instance;

  static final StatementBatchesService instance = StatementBatchesService();

  final AppDB _db;

  Future<String> commit({
    required String accountId,
    required List<TransactionInDB> transactionsToInsert,
    required List<String> activeModes,
  }) async {
    final batchId = generateUUID();
    final now = DateTime.now();
    final insertedIds = <String>[];

    await _db.transaction(() async {
      for (final tx in transactionsToInsert) {
        await _db.into(_db.transactions).insert(tx);
        insertedIds.add(tx.id);
      }

      await _db.into(_db.statementImportBatches).insert(
        StatementImportBatchInDB(
          id: batchId,
          accountId: accountId,
          createdAt: now,
          mode: jsonEncode(activeModes),
          transactionIds: jsonEncode(insertedIds),
        ),
      );
    });

    _db.markTablesUpdated([
      _db.accounts,
      _db.transactions,
      _db.statementImportBatches,
    ]);

    for (final tx in transactionsToInsert) {
      unawaited(FirebaseSyncService.instance.pushTransaction(tx));
    }

    return batchId;
  }

  Future<void> undo(String batchId) async {
    await _db.transaction(() async {
      final batch = await (_db.select(_db.statementImportBatches)
            ..where((t) => t.id.equals(batchId)))
          .getSingleOrNull();

      if (batch == null) {
        debugPrint('StatementBatchesService.undo: batch $batchId not found');
        return;
      }

      final decoded = jsonDecode(batch.transactionIds);
      final ids = <String>[];
      if (decoded is List) {
        for (final v in decoded) {
          if (v is String) ids.add(v);
        }
      }

      if (ids.isNotEmpty) {
        await (_db.delete(_db.transactions)
              ..where((t) => t.id.isIn(ids)))
            .go();

        for (final id in ids) {
          unawaited(FirebaseSyncService.instance.deleteTransaction(id));
        }
      }

      await (_db.delete(_db.statementImportBatches)
            ..where((t) => t.id.equals(batchId)))
          .go();
    });

    _db.markTablesUpdated([
      _db.accounts,
      _db.transactions,
      _db.statementImportBatches,
    ]);
  }

  /// Emite la lista de batches con `createdAt >= now - 7 días` para la cuenta
  /// indicada, ordenados por fecha descendente (más reciente primero).
  Stream<List<StatementImportBatchInDB>> watchRecentBatches(String accountId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return (_db.select(_db.statementImportBatches)
          ..where(
            (t) =>
                t.accountId.equals(accountId) &
                t.createdAt.isBiggerOrEqualValue(cutoff),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.createdAt,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  /// Decodifica la lista de `transactionIds` de un batch, tolerante a datos
  /// corruptos (devuelve lista vacía si falla el decode).
  List<String> decodeTransactionIds(StatementImportBatchInDB batch) {
    try {
      final decoded = jsonDecode(batch.transactionIds);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // ignore
    }
    return const <String>[];
  }

  Future<void> purge() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final deleted = await (_db.delete(_db.statementImportBatches)
          ..where((t) => t.createdAt.isSmallerThanValue(cutoff)))
        .go();
    if (deleted > 0) {
      debugPrint(
        'StatementBatchesService.purge: removed $deleted stale batch(es)',
      );
      _db.markTablesUpdated([_db.statementImportBatches]);
    }
  }
}
