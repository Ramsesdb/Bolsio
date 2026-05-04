import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nitido/core/database/services/app-data/app_data_service.dart';
import 'package:nitido/core/database/services/category/category_service.dart';
import 'package:nitido/core/database/services/currency/currency_service.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/database/sql/initial/seed.dart';
import 'package:nitido/core/database/utils/database_enum.dart';
import 'package:nitido/core/database/utils/list_converters.dart';
import 'package:nitido/core/models/account/account.dart';
import 'package:nitido/core/models/budget/budget.dart';
import 'package:nitido/core/models/category/category.dart';
import 'package:nitido/core/models/date-utils/periodicity.dart';
import 'package:nitido/core/models/exchange-rate/exchange_rate.dart';
import 'package:nitido/core/models/filters/saved_filter.dart';
import 'package:nitido/core/models/goal/goal.dart';
import 'package:nitido/core/models/goal/goal_type.enum.dart';
import 'package:nitido/core/models/debt/debt.dart';
import 'package:nitido/core/models/debt/debt_direction.enum.dart';
import 'package:nitido/core/models/transaction/transaction.dart';
import 'package:nitido/core/models/transaction/transaction_status.enum.dart';
import 'package:nitido/core/models/transaction/transaction_type.enum.dart';
import 'package:nitido/core/utils/logger.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

part 'app_db.g.dart';

@DriftDatabase(
  include: {'sql/initial/tables.drift', 'sql/queries/select-full-data.drift'},
)
class AppDB extends _$AppDB {
  AppDB._({
    required this.dbName,
    required this.inMemory,
    required this.logStatements,
  }) : _isTestInstance = false,
       super(openConnection(dbName, logStatements: logStatements));

  /// Constructor for unit/integration tests using an in-memory database.
  /// Bypasses file-based connection and the production migration/seeder logic.
  /// The [_isTestInstance] flag causes [migration] to skip `beforeOpen` hooks
  /// that depend on Flutter bindings (path_provider, asset bundle, etc.).
  AppDB.forTesting(super.executor)
    : dbName = 'test.db',
      inMemory = true,
      logStatements = false,
      _isTestInstance = true;

  static final AppDB instance = AppDB._(
    dbName: 'database.db',
    inMemory: false,
    logStatements: false,
  );

  final String dbName;
  final bool inMemory;
  final bool logStatements;
  final bool _isTestInstance;

  /// Get the path to the DB, that is `xxxx/xxxx/.../filename.db`
  Future<String> get databasePath async =>
      join((await getApplicationDocumentsDirectory()).path, dbName);

  /// Version numbers that are permanently skipped in the migration sequence.
  ///
  /// v10 — Introduced by upstream branch `feat/debts` (table `debts` +
  /// `transactions.debtId` FK). That branch was never merged into main.
  /// The gap is **intentional and permanent**. Users skip from v9 → v11
  /// without issue because Nitido never shipped v10.
  ///
  /// IMPORTANT: Any future migration must renumber from v30+ to avoid
  /// accidentally filling this gap and corrupting existing installs.
  static const _kSkippedMigrations = {10};

  Future<void> migrateDB(int from, int to) async {
    Logger.printDebug('Executing migrations from previous version [$from]...');

    await UserSettingService.instance.initializeGlobalStateMap();
    await AppDataService.instance.initializeGlobalStateMap();

    for (var i = from + 1; i <= to; i++) {
      // v10 is permanently skipped — see _kSkippedMigrations comment above.
      if (_kSkippedMigrations.contains(i)) {
        Logger.printDebug('Skipping migration v$i (permanently excluded).');
        continue;
      }

      Logger.printDebug('Migrating database to v$i...');

      try {
        final initialSQL = await rootBundle.loadString(
          'assets/sql/migrations/v$i.sql',
        );

        await transaction(() async {
          for (final sqlStatement in splitSQLStatements(initialSQL)) {
            Logger.printDebug(
              'Running custom statement: ${sqlStatement.substring(0, sqlStatement.length > 30 ? 30 : sqlStatement.length)}...',
            );
            await customStatement(sqlStatement);
          }

          await AppDataService.instance.setItem(
            AppDataKey.dbVersion,
            i.toStringAsFixed(0),
          );
        });
      } catch (e, stack) {
        Logger.recordError(
          e,
          stack,
          reason:
              'Migration v$i failed (from=$from, to=$to). '
              'DB version NOT advanced.',
        );
        rethrow;
      }
    }

    Logger.printDebug('Migration completed!');
  }

  @override
  int get schemaVersion => 29;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      beforeOpen: (details) async {
        // Test instances skip production hooks that require Flutter bindings
        // (path_provider, rootBundle, singleton services, etc.).
        if (_isTestInstance) return;

        Logger.printDebug(
          'DB found! Version ${details.versionNow} (previous was ${details.versionBefore}). Path to DB -> ${await databasePath}',
        );

        if (details.wasCreated) {
          Logger.printDebug('Executing seeders... Populating the database...');

          try {
            final initialDbSeedersStatements = [
              await settingsInitialSeedSQL(),
              appDataInitialSeedSQL(schemaVersion),
            ];

            for (final sqlStatement in initialDbSeedersStatements) {
              await customStatement(sqlStatement);
            }

            await CategoryService.instance.initializeCategories();
            await CurrencyService.instance.initializeCurrencies();

            Logger.printDebug('Initial data correctly inserted!');
          } catch (e) {
            Logger.printDebug('ERROR: $e');
            throw Exception(e);
          }
        }

        await customStatement('PRAGMA foreign_keys = ON');
        await customStatement('PRAGMA journal_mode = WAL;');
        await customStatement('PRAGMA busy_timeout = 5000;');

        final dbVersion = int.parse(
          (await AppDataService.instance
              .getAppDataItem(AppDataKey.dbVersion)
              .first)!,
        );

        if (dbVersion < schemaVersion) {
          await migrateDB(dbVersion, schemaVersion);
        }

        Logger.printDebug('DB Opened!');
      },
      onCreate: (m) async {
        Logger.printDebug('Creating database tables...');

        // Create all tables from `sql/initial/tables.drift`. We have also the schema in SQLite format in the assets folder
        await m.createAll();

        Logger.printDebug('Database tables created!');
      },
      onUpgrade: (m, from, to) {
        // The migration (if applied) is already done when the DB is opened. For instance, we have nothing to do here.
        return Future(() => null);
      },
    );
  }
}

LazyDatabase openConnection(String dbName, {bool logStatements = false}) {
  return LazyDatabase(() async {
    // Should be in the same route as the indicated in the databasePath getter of the AppDB class
    final file = File(
      join((await getApplicationDocumentsDirectory()).path, dbName),
    );

    return NativeDatabase.createBackgroundConnection(
      file,
      logStatements: logStatements,
      setup: (rawDb) => rawDb.execute('PRAGMA busy_timeout = 5000;'),
    );
  });
}

/// Splits a string containing multiple SQL statements into a list of individual statements.
///
/// This function takes a string of SQL commands separated by semicolons and
/// splits them into individual statements.
///
/// Example:
/// ```dart
/// String sql = "CREATE TABLE users (id INT); INSERT INTO users (id) VALUES (1);";
/// List<String> statements = splitSQLStatements(sql);
/// Logger.printDebug(statements); // Output: ["CREATE TABLE users (id INT)", "INSERT INTO users (id) VALUES (1)"]
/// ```
///
/// [sqliteStr] - The input string containing multiple SQL statements.
///
/// Returns a list of individual SQL statements.
List<String> splitSQLStatements(String sqliteStr) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inLineComment = false;
  var inBlockComment = false;
  var inSingleQuote = false;
  var inDoubleQuote = false;

  for (var i = 0; i < sqliteStr.length; i++) {
    final ch = sqliteStr[i];
    final next = i + 1 < sqliteStr.length ? sqliteStr[i + 1] : '';

    if (inLineComment) {
      buffer.write(ch);
      if (ch == '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      buffer.write(ch);
      if (ch == '*' && next == '/') {
        buffer.write(next);
        i++;
        inBlockComment = false;
      }
      continue;
    }
    if (inSingleQuote) {
      buffer.write(ch);
      if (ch == "'") inSingleQuote = false;
      continue;
    }
    if (inDoubleQuote) {
      buffer.write(ch);
      if (ch == '"') inDoubleQuote = false;
      continue;
    }

    if (ch == '-' && next == '-') {
      inLineComment = true;
      buffer.write(ch);
      continue;
    }
    if (ch == '/' && next == '*') {
      inBlockComment = true;
      buffer.write(ch);
      continue;
    }
    if (ch == "'") {
      inSingleQuote = true;
      buffer.write(ch);
      continue;
    }
    if (ch == '"') {
      inDoubleQuote = true;
      buffer.write(ch);
      continue;
    }

    if (ch == ';') {
      final stmt = buffer.toString().trim();
      if (stmt.isNotEmpty) statements.add(stmt);
      buffer.clear();
      continue;
    }

    buffer.write(ch);
  }

  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) statements.add(tail);
  return statements;
}
