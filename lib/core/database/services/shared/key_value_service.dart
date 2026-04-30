import 'package:drift/drift.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/shared/key_value_pair.dart';

/// Hook invoked by [KeyValueService.setItem] when `updateGlobalState` is
/// true. The app's root state widget assigns this in `main.dart` so the
/// service does not need to import the (heavy) `main.dart` module — that
/// transitive import was pulling broken pre-existing files into the test
/// graph and blocking unit tests that touch user_setting_service.
///
/// Tests can leave this `null` (the default) — the no-op fallback below
/// matches the original behavior when no `_InitializeAppState` is mounted.
void Function()? onGlobalAppStateRefresh;

/// Base service to handle key-value pairs for any table
abstract class KeyValueService<
  KeyType extends Enum,
  TableType extends Table,
  RowType
> {
  final AppDB db;
  final TableInfo<TableType, RowType> table;
  final Map<KeyType, String?> globalStateMap;
  final KeyValuePairInDB<KeyType> Function(RowType) rowToKeyPairInstance;
  final Insertable<RowType> Function(KeyValuePairInDB<KeyType>) toDbRow;

  KeyValueService({
    required this.db,
    required this.table,
    required this.globalStateMap,
    required this.rowToKeyPairInstance,
    required this.toDbRow,
  });

  Future<void> initializeGlobalStateMap() async {
    final savedSettings = await db.select(table).get();

    for (final savedSetting in savedSettings.map(rowToKeyPairInstance)) {
      globalStateMap[savedSetting.key] = savedSetting.value;
    }
  }

  Future<bool> setItem(
    KeyType itemKey,
    String? itemValue, {
    bool updateGlobalState = false,
  }) async {
    final previousValue = globalStateMap[itemKey];

    if (previousValue == itemValue) {
      return false;
    }

    globalStateMap[itemKey] = itemValue;

    try {
      await db
          .into(table)
          .insert(
            toDbRow(KeyValuePairInDB(key: itemKey, value: itemValue)),
            mode: InsertMode.insertOrReplace,
          );

      if (updateGlobalState == true) {
        onGlobalAppStateRefresh?.call();
      }
    } catch (e) {
      globalStateMap[itemKey] = previousValue; // Restore previous value
      rethrow; // Allow caller to handle the error
    }

    return true;
  }

  Stream<List<RowType>> getItemsFromDB(
    Expression<bool> Function(TableType) filter,
  ) {
    return (db.select(table)..where(filter)).watch();
  }
}
