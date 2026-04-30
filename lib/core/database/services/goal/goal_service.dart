import 'dart:async';

import 'package:drift/drift.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/models/goal/goal.dart';
import 'package:bolsio/core/services/firebase_sync_service.dart';

class GoalService {
  final AppDB db;

  GoalService._(this.db);
  static final GoalService instance = GoalService._(AppDB.instance);

  Future<bool> insertGoal(Goal goal) async {
    final goalInDb = GoalInDB(
      id: goal.id,
      name: goal.name,
      amount: goal.amount,
      initialAmount: goal.initialAmount,
      type: goal.type,
      startDate: goal.startDate,
      endDate: goal.endDate,
      filterID: goal.filterID,
    );
    final trFiltersInDb = goal.trFilters.toDBModel(id: goal.filterID);

    final toReturn = await db.transaction(() async {
      await db.into(db.transactionFilterSets).insert(trFiltersInDb);
      await db.into(db.goals).insert(goalInDb);
      return true;
    });

    unawaited(FirebaseSyncService.instance
        .pushGoal(goalInDb, trFilters: trFiltersInDb));
    return toReturn;
  }

  Future<bool> deleteGoal(String id) async {
    final toReturn = await db.transaction(() async {
      // Delete the filter first:
      final goalToDelete = await (db.select(
        db.goals,
      )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

      if (goalToDelete == null) {
        return false;
      }

      await (db.delete(
        db.transactionFilterSets,
      )..where((tbl) => tbl.id.equals(goalToDelete.filterID))).go();

      await (db.delete(db.goals)..where((tbl) => tbl.id.isValue(id))).go();

      return true;
    });

    if (toReturn) {
      unawaited(FirebaseSyncService.instance.deleteGoal(id));
    }
    return toReturn;
  }

  Future<bool> updateGoal(Goal goal) {
    return db.transaction(() async {
      await deleteGoal(goal.id);

      await insertGoal(goal);

      return true;
    });
  }

  Stream<List<Goal>> getGoals({
    Expression<bool> Function(Goals, TransactionFilterSets)? predicate,
    OrderBy Function(Goals, TransactionFilterSets)? orderBy,
    int? limit,
    int? offset,
  }) {
    return db
        .getGoalsWithFullData(
          predicate: predicate,
          orderBy: orderBy,
          limit: (b, trFilter) => Limit(limit ?? -1, offset),
        )
        .watch();
  }

  Stream<Goal?> getGoalById(String id) {
    return getGoals(
      predicate: (p0, trFilter) => p0.id.equals(id),
      limit: 1,
    ).map((res) => res.firstOrNull);
  }
}
