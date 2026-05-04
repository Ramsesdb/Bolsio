import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/database/app_db.dart';

/// Tests for the atomicity of migration SQL execution via Drift's
/// `transaction()` + `customStatement()` API.
///
/// These tests do NOT exercise `migrateDB()` directly — that method
/// depends on `rootBundle` (Flutter asset binding) and singleton
/// `AppDataService`/`UserSettingService`, which require a full Flutter
/// harness unavailable in unit tests (see `currency_mode_migration_test.dart`
/// for the documented reasoning).
///
/// Instead, they verify the underlying guarantee that `migrateDB()` now
/// relies on: Drift's `transaction()` rolls back *all* `customStatement()`
/// calls within it if any one throws. This is the property that makes the
/// per-version wrapping safe.
///
/// Three scenarios:
///   1. Valid SQL inside a transaction applies cleanly.
///   2. Invalid SQL inside a transaction causes a full rollback — the DB
///      state before the transaction is fully preserved.
///   3. A chain of 3 operations where the second fails: the first (committed
///      before the failing transaction) persists; the second and third
///      (inside the failing transaction) are rolled back.
void main() {
  late AppDB db;

  setUp(() {
    db = AppDB.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('migration atomicity', () {
    test('valid SQL in transaction applies and does not throw', () async {
      // Create a test table inside a transaction — should succeed.
      await db.transaction(() async {
        await db.customStatement(
          'CREATE TABLE IF NOT EXISTS _test_atomic (id INTEGER PRIMARY KEY)',
        );
      });

      // Verify table exists by inserting a row — must not throw.
      await expectLater(
        db.customStatement('INSERT INTO _test_atomic VALUES (1)'),
        completes,
      );
    });

    test(
      'invalid SQL in transaction rolls back — previous state intact',
      () async {
        // Create a known-good table *outside* any transaction.
        await db.customStatement(
          'CREATE TABLE IF NOT EXISTS _test_rollback (id INTEGER PRIMARY KEY)',
        );

        // Run a transaction that creates another table AND then fails.
        await expectLater(
          db.transaction(() async {
            await db.customStatement(
              'CREATE TABLE _test_rollback_inner (id INTEGER PRIMARY KEY)',
            );
            // This throws — invalid SQL triggers rollback of the whole tx.
            await db.customStatement('THIS IS NOT VALID SQL');
          }),
          throwsA(anything),
        );

        // The table created *outside* the failed transaction must still exist.
        await expectLater(
          db.customStatement('INSERT INTO _test_rollback VALUES (1)'),
          completes,
        );

        // The table created *inside* the failed transaction must NOT exist.
        await expectLater(
          db.customStatement('INSERT INTO _test_rollback_inner VALUES (1)'),
          throwsA(anything),
        );
      },
    );

    test('chain of 3 operations: second fails → first persists, '
        'second and third are rolled back', () async {
      // Operation 1: create table A outside any transaction (will succeed
      // and remain committed regardless of later failures).
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS _chain_a (id INTEGER PRIMARY KEY)',
      );

      // Operations 2 & 3 inside a single transaction.
      // Op 2 (create _chain_b) would succeed on its own, but the
      // subsequent invalid SQL causes the whole transaction to roll back.
      // Op 3 (_chain_c) is never reached.
      await expectLater(
        db.transaction(() async {
          await db.customStatement(
            'CREATE TABLE _chain_b (id INTEGER PRIMARY KEY)',
          );
          // Invalid SQL — triggers rollback.
          await db.customStatement('INVALID SQL STATEMENT');
          // Unreachable — kept to document intent.
          await db.customStatement(
            'CREATE TABLE _chain_c (id INTEGER PRIMARY KEY)',
          );
        }),
        throwsA(anything),
      );

      // Table A (created before the failed transaction) still exists.
      await expectLater(
        db.customStatement('INSERT INTO _chain_a VALUES (1)'),
        completes,
      );

      // Table B (created inside the failed transaction) does NOT exist.
      await expectLater(
        db.customStatement('INSERT INTO _chain_b VALUES (1)'),
        throwsA(anything),
      );

      // Table C (inside the failed transaction, after the failing statement)
      // does NOT exist either.
      await expectLater(
        db.customStatement('INSERT INTO _chain_c VALUES (1)'),
        throwsA(anything),
      );
    });
  });
}
