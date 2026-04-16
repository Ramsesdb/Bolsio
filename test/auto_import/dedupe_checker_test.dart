import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal_status.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/services/auto_import/dedupe/dedupe_checker.dart';

AppDB _createTestDb() {
  return AppDB.forTesting(NativeDatabase.memory());
}

/// Helper to insert a transaction directly into the DB for testing.
Future<void> _insertTransaction(
  AppDB db, {
  required String id,
  required String accountId,
  required double value,
  required DateTime date,
  String? notes,
  String? categoryId,
}) async {
  await db.into(db.transactions).insert(TransactionsCompanion(
        id: Value(id),
        accountID: Value(accountId),
        value: Value(value),
        date: Value(date),
        type: const Value(TransactionType.income),
        notes: Value(notes),
        categoryID: Value(categoryId),
      ));
}

/// Helper to insert an account directly into the DB for testing.
Future<void> _insertAccount(
  AppDB db, {
  required String id,
  required String name,
  String currencyId = 'VES',
}) async {
  // First ensure the currency exists
  await db.into(db.currencies).insertOnConflictUpdate(CurrenciesCompanion(
        code: Value(currencyId),
        symbol: const Value('Bs.'),
        name: const Value('Bolivar'),
        decimalPlaces: const Value(2),
        isDefault: const Value(false),
        type: const Value(0),
      ));

  await db.into(db.accounts).insert(AccountsCompanion(
        id: Value(id),
        name: Value(name),
        iniValue: const Value(0),
        date: Value(DateTime(2026, 1, 1)),
        type: const Value(AccountType.normal),
        iconId: const Value('money'),
        displayOrder: const Value(0),
        currencyId: Value(currencyId),
      ));
}

/// Helper to insert a category directly into the DB for testing.
Future<void> _insertCategory(
  AppDB db, {
  required String id,
  required String name,
}) async {
  await db.into(db.categories).insert(CategoriesCompanion(
        id: Value(id),
        name: Value(name),
        iconId: const Value('default'),
        displayOrder: const Value(0),
        type: const Value(CategoryType.B),
        color: const Value('#000000'),
      ));
}

TransactionProposal _makeProposal({
  double amount = 500.0,
  String? bankRef,
  String? accountId = 'acc-bdv-001',
  DateTime? date,
}) {
  return TransactionProposal.newProposal(
    accountId: accountId,
    amount: amount,
    currencyId: 'VES',
    date: date ?? DateTime(2026, 4, 15, 14, 0),
    type: TransactionType.income,
    rawText: 'Test SMS text',
    channel: CaptureChannel.sms,
    confidence: 0.95,
    bankRef: bankRef,
  );
}

void main() {
  late AppDB db;
  late PendingImportService pendingImportService;
  late DedupeChecker checker;

  setUp(() async {
    db = _createTestDb();
    await db.customStatement('PRAGMA foreign_keys = OFF');
    pendingImportService = PendingImportService.forTesting(db);
    checker = DedupeChecker.forTesting(
      db: db,
      pendingImportService: pendingImportService,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('DedupeChecker', () {
    test(
        'detects duplicate when transaction exists with matching bankRef in notes',
        () async {
      // Insert account and category first (needed for FK in some configs)
      await _insertAccount(db, id: 'acc-bdv-001', name: 'Banco de Venezuela');
      await _insertCategory(db, id: 'cat-1', name: 'General');

      // Insert a transaction with the bankRef in its notes
      await _insertTransaction(
        db,
        id: 'tx-existing-1',
        accountId: 'acc-bdv-001',
        value: 500.0,
        date: DateTime(2026, 4, 15, 14, 0),
        notes: '[auto:sms:bdv] ref=999111',
        categoryId: 'cat-1',
      );

      // A proposal with the same bankRef should be detected as duplicate
      final proposal = _makeProposal(bankRef: '999111');
      final isDuplicate = await checker.check(proposal);
      expect(isDuplicate, isTrue);
    });

    test(
        'detects duplicate when pending_import exists with matching bankRef',
        () async {
      // Insert a pending import with bankRef
      final existingProposal = _makeProposal(bankRef: '888777');
      await pendingImportService.insertPendingImport(
        existingProposal.toCompanion(
            status: TransactionProposalStatus.pending),
      );

      // A new proposal with the same bankRef should be detected as duplicate
      final newProposal = _makeProposal(bankRef: '888777');
      final isDuplicate = await checker.check(newProposal);
      expect(isDuplicate, isTrue);
    });

    test(
        'detects duplicate by amount+account+date within 2h window (no bankRef)',
        () async {
      await _insertAccount(db, id: 'acc-bdv-001', name: 'Banco de Venezuela');
      await _insertCategory(db, id: 'cat-1', name: 'General');

      // Insert a transaction with amount=500, same account, within 2h window
      await _insertTransaction(
        db,
        id: 'tx-existing-2',
        accountId: 'acc-bdv-001',
        value: 500.0,
        date: DateTime(2026, 4, 15, 13, 0), // 1 hour before proposal
        categoryId: 'cat-1',
      );

      // Proposal without bankRef, same amount, same account, within 2h
      final proposal = _makeProposal(
        bankRef: null,
        amount: 500.0,
        accountId: 'acc-bdv-001',
        date: DateTime(2026, 4, 15, 14, 0),
      );
      final isDuplicate = await checker.check(proposal);
      expect(isDuplicate, isTrue);
    });

    test('no duplicate when amount matches but date is outside 2h window',
        () async {
      await _insertAccount(db, id: 'acc-bdv-001', name: 'Banco de Venezuela');
      await _insertCategory(db, id: 'cat-1', name: 'General');

      // Insert a transaction 5 hours before
      await _insertTransaction(
        db,
        id: 'tx-existing-3',
        accountId: 'acc-bdv-001',
        value: 500.0,
        date: DateTime(2026, 4, 15, 9, 0), // 5 hours before proposal at 14:00
        categoryId: 'cat-1',
      );

      final proposal = _makeProposal(
        bankRef: null,
        amount: 500.0,
        accountId: 'acc-bdv-001',
        date: DateTime(2026, 4, 15, 14, 0),
      );
      final isDuplicate = await checker.check(proposal);
      expect(isDuplicate, isFalse);
    });

    test('no duplicate when same amount and date but different accountId',
        () async {
      await _insertAccount(db, id: 'acc-bdv-001', name: 'Banco de Venezuela');
      await _insertAccount(db, id: 'acc-bnc-001', name: 'BNC');
      await _insertCategory(db, id: 'cat-1', name: 'General');

      // Insert transaction on a DIFFERENT account
      await _insertTransaction(
        db,
        id: 'tx-existing-4',
        accountId: 'acc-bnc-001',
        value: 500.0,
        date: DateTime(2026, 4, 15, 14, 0),
        categoryId: 'cat-1',
      );

      // Proposal on acc-bdv-001 — should NOT match the bnc transaction
      final proposal = _makeProposal(
        bankRef: null,
        amount: 500.0,
        accountId: 'acc-bdv-001',
        date: DateTime(2026, 4, 15, 14, 0),
      );
      final isDuplicate = await checker.check(proposal);
      expect(isDuplicate, isFalse);
    });
  });
}
