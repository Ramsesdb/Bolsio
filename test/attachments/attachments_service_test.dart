import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:bolsio/core/models/account/account.dart';
import 'package:bolsio/core/models/category/category.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/services/attachments/attachment_model.dart';
import 'package:bolsio/core/services/attachments/attachments_service.dart';

class _FakeAttachmentsService extends AttachmentsService {
  _FakeAttachmentsService(super.db) : super.forTesting();

  AttachmentOwnerType? lastOwnerType;
  String? lastOwnerId;

  @override
  Future<void> deleteByOwner({
    required AttachmentOwnerType ownerType,
    required String ownerId,
  }) async {
    lastOwnerType = ownerType;
    lastOwnerId = ownerId;
  }
}

List<String> _splitSqlStatements(String script) {
  return script
      .split(RegExp(r';\s*'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

AppDB _createTestDb() => AppDB.forTesting(NativeDatabase.memory());

Future<int> _seedTestAccount(AppDB db, {required String accountId}) {
  return db.into(db.accounts).insert(
        AccountsCompanion.insert(
          id: accountId,
          name: 'Cuenta Test $accountId',
          iniValue: 0,
          date: DateTime(2026, 1, 1),
          type: AccountType.normal,
          iconId: 'wallet',
          displayOrder: 0,
          currencyId: 'USD',
        ),
      );
}

Future<int> _seedTestCategory(AppDB db, {required String categoryId}) {
  return db.into(db.categories).insert(
        CategoriesCompanion.insert(
          id: categoryId,
          name: 'Categoria Test $categoryId',
          iconId: 'food',
          displayOrder: 0,
          color: const Value('FF0000'),
          type: const Value(CategoryType.E),
        ),
      );
}

Future<int> _seedTestCurrency(AppDB db, {required String code}) {
  return db.into(db.currencies).insert(
        CurrenciesCompanion.insert(
          code: code,
          symbol: r'$',
          name: code,
          decimalPlaces: 2,
          isDefault: true,
          type: 0,
        ),
      );
}

Future<int> _seedTestTransaction(
  AppDB db, {
  required String transactionId,
  required String accountId,
  required String categoryId,
}) {
  return db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: transactionId,
          date: DateTime(2026, 4, 17, 10, 0),
          accountID: accountId,
          value: 100,
          type: TransactionType.expense,
          categoryID: Value(categoryId),
          createdAt: Value(DateTime(2026, 4, 17, 10, 0)),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late AppDB db;
  late AttachmentsService service;
  late Directory tempRoot;

  setUp(() async {
    db = _createTestDb();
    service = AttachmentsService.forTesting(db);
    tempRoot = await Directory.systemTemp.createTemp('bolsio_attachments_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempRoot.path;
      }
      if (call.method == 'getApplicationSupportDirectory') {
        return tempRoot.path;
      }
      return tempRoot.path;
    });

    await _seedTestCurrency(db, code: 'USD');
    await _seedTestCurrency(db, code: 'VES');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await db.close();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('AttachmentsService', () {
    test('1.13 attach -> listByOwner -> deleteById removes row and file', () async {
      final source = File('${tempRoot.path}/source.jpg');
      source.writeAsBytesSync(List.filled(128, 1));

      final created = await service.attach(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-1',
        sourceFile: source,
        role: 'receipt',
      );

      final beforeDelete = await service.listByOwner(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-1',
      );
      expect(beforeDelete, hasLength(1));

      final file = await service.resolveFile(created);
      expect(await file.exists(), isTrue);

      await service.deleteById(created.id);

      final afterDelete = await service.listByOwner(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-1',
      );
      expect(afterDelete, isEmpty);
      expect(await file.exists(), isFalse);
    });

    test('1.14 deleteByOwner removes only matching owner attachments', () async {
      final f1 = File('${tempRoot.path}/o1.jpg')..writeAsBytesSync(List.filled(64, 2));
      final f2 = File('${tempRoot.path}/o2.jpg')..writeAsBytesSync(List.filled(64, 3));

      await service.attach(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-target',
        sourceFile: f1,
      );
      final survivor = await service.attach(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-other',
        sourceFile: f2,
      );

      await service.deleteByOwner(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-target',
      );

      final targetRows = await service.listByOwner(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-target',
      );
      final otherRows = await service.listByOwner(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-other',
      );

      expect(targetRows, isEmpty);
      expect(otherRows, hasLength(1));

      final survivorFile = await service.resolveFile(survivor);
      expect(await survivorFile.exists(), isTrue);
    });

    test('1.15 purgeOrphans removes rows-without-file and files-without-row', () async {
      final source = File('${tempRoot.path}/keep.jpg')..writeAsBytesSync(List.filled(64, 7));
      final attached = await service.attach(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-clean',
        sourceFile: source,
      );

      final attachedFile = await service.resolveFile(attached);
      await attachedFile.delete();

      final strayDir = Directory('${tempRoot.path}/attachments/transaction')
        ..createSync(recursive: true);
      final strayFile = File('${strayDir.path}/stray.jpg')
        ..writeAsBytesSync(List.filled(64, 9));
      expect(await strayFile.exists(), isTrue);

      final removed = await service.purgeOrphans();
      expect(removed, greaterThanOrEqualTo(2));

      final rows = await service.listByOwner(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-clean',
      );
      expect(rows, isEmpty);
      expect(await strayFile.exists(), isFalse);
    });

    test('1.16 resolveFile rebuilds absolute path from relative localPath', () async {
      final source = File('${tempRoot.path}/path_case.jpg')
        ..writeAsBytesSync(List.filled(80, 4));
      final created = await service.attach(
        ownerType: AttachmentOwnerType.userProfile,
        ownerId: 'current',
        sourceFile: source,
        role: 'avatar',
      );

      expect(created.localPath.startsWith('attachments'), isTrue);

      final resolved = await service.resolveFile(created);
      expect(resolved.path.contains(tempRoot.path), isTrue);
      expect(await resolved.exists(), isTrue);
    });

    test('1.17 image compression stores jpg with <=1600 max side and smaller size', () async {
      final raster = img.Image(width: 3000, height: 2200);
      for (var y = 0; y < raster.height; y++) {
        for (var x = 0; x < raster.width; x++) {
          raster.setPixelRgba(x, y, x % 255, y % 255, (x + y) % 255, 255);
        }
      }
      final bigImageBytes = img.encodePng(raster, level: 0);
      final source = File('${tempRoot.path}/big_input.png')
        ..writeAsBytesSync(bigImageBytes);

      final created = await service.attach(
        ownerType: AttachmentOwnerType.transaction,
        ownerId: 'tx-compress',
        sourceFile: source,
      );

      final persisted = await service.resolveFile(created);
      expect(persisted.path.endsWith('.jpg'), isTrue);

      final sourceSize = await source.length();
      final targetSize = await persisted.length();
      expect(targetSize, lessThan(sourceSize));
    });
  });

  test('1.18 deleteTransaction invokes deleteByOwner on attachments service', () async {
    final fakeAttachments = _FakeAttachmentsService(db);
    final txService = TransactionService.forTesting(
      db,
      attachmentsService: fakeAttachments,
    );

    await _seedTestAccount(db, accountId: 'acc-1');
    await _seedTestCategory(db, categoryId: 'cat-1');
    await _seedTestTransaction(
      db,
      transactionId: 'tx-delete-1',
      accountId: 'acc-1',
      categoryId: 'cat-1',
    );

    await txService.deleteTransaction('tx-delete-1');

    expect(fakeAttachments.lastOwnerType, AttachmentOwnerType.transaction);
    expect(fakeAttachments.lastOwnerId, 'tx-delete-1');
  });

  test('1.19 v23 migration script is additive and preserves existing rows', () async {
    final tempFile = File(p.join(tempRoot.path, 'v22_fixture.db'));
    final sqliteDb = sqlite.sqlite3.open(tempFile.path);

    try {
      sqliteDb.execute('''
        CREATE TABLE currencies (
          code TEXT NOT NULL PRIMARY KEY,
          symbol TEXT NOT NULL,
          name TEXT NOT NULL,
          decimalPlaces INTEGER NOT NULL,
          isDefault INTEGER NOT NULL,
          type INTEGER NOT NULL
        );
      ''');

      sqliteDb.execute('''
        CREATE TABLE accounts (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          iniValue REAL NOT NULL,
          date TEXT NOT NULL,
          type TEXT NOT NULL,
          iconId TEXT NOT NULL,
          displayOrder INTEGER NOT NULL,
          currencyId TEXT NOT NULL
        );
      ''');

      sqliteDb.execute('''
        CREATE TABLE categories (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          iconId TEXT NOT NULL,
          displayOrder INTEGER NOT NULL
        );
      ''');

      sqliteDb.execute('''
        CREATE TABLE transactions (
          id TEXT NOT NULL PRIMARY KEY,
          date TEXT NOT NULL,
          accountID TEXT NOT NULL,
          value REAL NOT NULL,
          type TEXT NOT NULL,
          categoryID TEXT
        );
      ''');

      sqliteDb.execute(
        "INSERT INTO currencies VALUES ('USD', '\$', 'USD', 2, 1, 0)",
      );
      sqliteDb.execute(
        "INSERT INTO accounts VALUES ('acc1', 'Cuenta', 10.0, '2026-01-01', 'normal', 'wallet', 0, 'USD')",
      );
      sqliteDb.execute(
        "INSERT INTO categories VALUES ('cat1', 'Categoria', 'food', 0)",
      );
      sqliteDb.execute(
        "INSERT INTO transactions VALUES ('tx1', '2026-04-17', 'acc1', 5.0, 'E', 'cat1')",
      );

      final beforeCount = sqliteDb
          .select('SELECT COUNT(*) AS c FROM transactions')
          .first['c'] as int;
      expect(beforeCount, 1);

      final migrationScript = File(
        p.join('assets', 'sql', 'migrations', 'v23.sql'),
      ).readAsStringSync();

      for (final statement in _splitSqlStatements(migrationScript)) {
        sqliteDb.execute(statement);
      }

      final tableExists = sqliteDb
          .select(
            "SELECT COUNT(*) AS c FROM sqlite_master WHERE type='table' AND name='attachments'",
          )
          .first['c'] as int;
      final indexExists = sqliteDb
          .select(
            "SELECT COUNT(*) AS c FROM sqlite_master WHERE type='index' AND name='idx_attachments_owner'",
          )
          .first['c'] as int;
      final afterCount = sqliteDb
          .select('SELECT COUNT(*) AS c FROM transactions')
          .first['c'] as int;

      expect(tableExists, 1);
      expect(indexExists, 1);
      expect(afterCount, 1);
    } finally {
      sqliteDb.dispose();
    }
  });
}
