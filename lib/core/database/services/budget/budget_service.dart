import 'dart:async';

import 'package:drift/drift.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/models/budget/budget.dart';
import 'package:wallex/core/services/firebase_sync_service.dart';

class BudgetServive {
  final AppDB db;

  BudgetServive._(this.db);
  static final BudgetServive instance = BudgetServive._(AppDB.instance);

  Future<bool> insertBudget(Budget budget) async {
    final budgetInDb = BudgetInDB(
      id: budget.id,
      name: budget.name,
      limitAmount: budget.limitAmount,
      intervalPeriod: budget.intervalPeriod,
      startDate: budget.startDate,
      endDate: budget.endDate,
      filterID: budget.filterID,
    );
    final trFiltersInDb = budget.trFilters.toDBModel(id: budget.filterID);

    final toReturn = await db.transaction(() async {
      await db.into(db.transactionFilterSets).insert(trFiltersInDb);
      await db.into(db.budgets).insert(budgetInDb);
      return true;
    });

    unawaited(FirebaseSyncService.instance
        .pushBudget(budgetInDb, trFilters: trFiltersInDb));
    return toReturn;
  }

  Future<bool> deleteBudget(String id) async {
    final toReturn = await db.transaction(() async {
      // Delete the filter first:
      final budgetToDelete = await (db.select(
        db.budgets,
      )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

      if (budgetToDelete == null) {
        return false;
      }

      await (db.delete(
        db.transactionFilterSets,
      )..where((tbl) => tbl.id.equals(budgetToDelete.filterID))).go();

      await (db.delete(db.budgets)..where((tbl) => tbl.id.isValue(id))).go();

      return true;
    });

    if (toReturn) {
      unawaited(FirebaseSyncService.instance.deleteBudget(id));
    }
    return toReturn;
  }

  Future<bool> updateBudget(Budget budget) {
    return db.transaction(() async {
      await deleteBudget(budget.id);

      await insertBudget(budget);

      return true;
    });
  }

  Stream<List<Budget>> getBudgets({
    Expression<bool> Function(Budgets, TransactionFilterSets)? predicate,
    OrderBy Function(Budgets, TransactionFilterSets)? orderBy,
    int? limit,
    int? offset,
  }) {
    return db
        .getBudgetsWithFullData(
          predicate: predicate,
          orderBy: orderBy,
          limit: (b, trFilter) => Limit(limit ?? -1, offset),
        )
        .watch();
  }

  Stream<Budget?> getBudgetById(String id) {
    return getBudgets(
      predicate: (p0, trFilter) => p0.id.equals(id),
      limit: 1,
    ).map((res) => res.firstOrNull);
  }
}
