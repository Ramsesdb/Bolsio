import 'dart:async';

import 'package:drift/drift.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/models/tags/tag.dart';
import 'package:wallex/core/services/firebase_sync_service.dart';

class TagService {
  final AppDB db;

  TagService._(this.db);
  static final TagService instance = TagService._(AppDB.instance);

  Future<int> insertTag(TagInDB tag) async {
    final toReturn = await db.into(db.tags).insert(tag);
    unawaited(FirebaseSyncService.instance.pushTag(tag));
    return toReturn;
  }

  Future<bool> updateTag(TagInDB tag) async {
    final toReturn = await db.update(db.tags).replace(tag);
    unawaited(FirebaseSyncService.instance.pushTag(tag));
    return toReturn;
  }

  Future<int> deleteTag(String tagId) async {
    final toReturn =
        await (db.delete(db.tags)..where((tbl) => tbl.id.equals(tagId))).go();
    unawaited(FirebaseSyncService.instance.deleteTag(tagId));
    return toReturn;
  }

  Future<void> linkTagsToTransaction({
    required String transactionId,
    required List<String> tagIds,
  }) {
    final db = AppDB.instance;

    return db.batch((batch) {
      for (final tagId in tagIds) {
        batch.insert(
          db.transactionTags,
          TransactionTag(transactionID: transactionId, tagID: tagId),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  Stream<List<Tag>> getTags({
    Expression<bool> Function(Tags)? filter,
    int? limit,
    int? offset,
  }) {
    limit ??= -1;

    return (db.select(db.tags)
          ..where(filter ?? (tbl) => const CustomExpression('(TRUE)'))
          ..orderBy([(acc) => OrderingTerm.asc(acc.displayOrder)])
          ..limit(limit, offset: offset))
        .watch()
        .map((event) => event.map((e) => Tag.fromTagInDB(e)).toList());
  }
}
