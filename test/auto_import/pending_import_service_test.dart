import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/database/app_db.dart';
import 'package:nitido/core/database/services/pending_import/pending_import_service.dart';
import 'package:nitido/core/models/auto_import/capture_channel.dart';
import 'package:nitido/core/models/auto_import/transaction_proposal.dart';
import 'package:nitido/core/models/auto_import/transaction_proposal_status.dart';
import 'package:nitido/core/models/transaction/transaction_type.enum.dart';

/// Creates an in-memory [AppDB] for testing with all tables created.
AppDB _createTestDb() {
  final db = AppDB.forTesting(NativeDatabase.memory());
  return db;
}

/// Helper to build a [PendingImportsCompanion] from a [TransactionProposal].
PendingImportsCompanion _makeCompanion({
  String? id,
  double amount = 23500.0,
  String currencyId = 'VES',
  TransactionType type = TransactionType.expense,
  String rawText = 'Realizaste un PagomovilBDV por Bs. 23.500,00',
  CaptureChannel channel = CaptureChannel.sms,
  double confidence = 0.95,
  String? bankRef,
  String? sender,
  TransactionProposalStatus status = TransactionProposalStatus.pending,
}) {
  final proposal = TransactionProposal.newProposal(
    amount: amount,
    currencyId: currencyId,
    date: DateTime(2026, 4, 15, 10, 30),
    type: type,
    rawText: rawText,
    channel: channel,
    confidence: confidence,
    bankRef: bankRef,
    sender: sender,
  );

  // If a specific id was requested, build manually
  final effectiveProposal = id != null
      ? TransactionProposal(
          id: id,
          amount: proposal.amount,
          currencyId: proposal.currencyId,
          date: proposal.date,
          type: proposal.type,
          rawText: proposal.rawText,
          channel: proposal.channel,
          confidence: proposal.confidence,
          bankRef: proposal.bankRef,
          sender: proposal.sender,
        )
      : proposal;

  return effectiveProposal.toCompanion(status: status);
}

void main() {
  late AppDB db;
  late PendingImportService service;

  setUp(() async {
    db = _createTestDb();
    // Create all tables defined in tables.drift
    await db.customStatement('PRAGMA foreign_keys = OFF');
    service = PendingImportService.forTesting(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('PendingImportService', () {
    test('insert + getPendingImports returns the inserted row', () async {
      final companion = _makeCompanion(
        id: 'test-id-001',
        bankRef: 'REF001',
        sender: '2662',
      );

      await service.insertPendingImport(companion);

      final results = await service.getPendingImports().first;

      expect(results, hasLength(1));
      expect(results.first.id, 'test-id-001');
      expect(results.first.amount, 23500.0);
      expect(results.first.currencyId, 'VES');
      expect(results.first.type, 'E');
      expect(results.first.rawText,
          'Realizaste un PagomovilBDV por Bs. 23.500,00');
      expect(results.first.channel, 'sms');
      expect(results.first.sender, '2662');
      expect(results.first.confidence, 0.95);
      expect(results.first.status, 'pending');
      expect(results.first.bankRef, 'REF001');
    });

    test('getPendingImports filters by status', () async {
      await service.insertPendingImport(_makeCompanion(
        id: 'pending-1',
        status: TransactionProposalStatus.pending,
      ));
      await service.insertPendingImport(_makeCompanion(
        id: 'confirmed-1',
        status: TransactionProposalStatus.confirmed,
      ));
      await service.insertPendingImport(_makeCompanion(
        id: 'rejected-1',
        status: TransactionProposalStatus.rejected,
      ));

      final pendingOnly = await service
          .getPendingImports(status: TransactionProposalStatus.pending)
          .first;
      expect(pendingOnly, hasLength(1));
      expect(pendingOnly.first.id, 'pending-1');

      final confirmedOnly = await service
          .getPendingImports(status: TransactionProposalStatus.confirmed)
          .first;
      expect(confirmedOnly, hasLength(1));
      expect(confirmedOnly.first.id, 'confirmed-1');

      final all = await service.getPendingImports().first;
      expect(all, hasLength(3));
    });

    test('updatePendingImportStatus updates status and createdTransactionId',
        () async {
      await service.insertPendingImport(_makeCompanion(
        id: 'update-test-1',
        status: TransactionProposalStatus.pending,
      ));

      // Update to confirmed with a createdTransactionId
      final updated = await service.updatePendingImportStatus(
        'update-test-1',
        TransactionProposalStatus.confirmed,
        createdTransactionId: 'tx-abc-123',
      );
      expect(updated, 1);

      final results = await service.getPendingImports().first;
      expect(results, hasLength(1));
      expect(results.first.status, 'confirmed');
      expect(results.first.createdTransactionId, 'tx-abc-123');
    });

    test('updatePendingImportStatus without createdTransactionId leaves it null',
        () async {
      await service.insertPendingImport(_makeCompanion(
        id: 'update-test-2',
        status: TransactionProposalStatus.pending,
      ));

      await service.updatePendingImportStatus(
        'update-test-2',
        TransactionProposalStatus.rejected,
      );

      final results = await service.getPendingImports().first;
      expect(results.first.status, 'rejected');
      expect(results.first.createdTransactionId, isNull);
    });

    test('watchPendingCount emits correct values', () async {
      // Initial count should be 0
      final count0 = await service.watchPendingCount().first;
      expect(count0, 0);

      // Insert a pending item
      await service.insertPendingImport(_makeCompanion(
        id: 'count-test-1',
        status: TransactionProposalStatus.pending,
      ));

      final count1 = await service.watchPendingCount().first;
      expect(count1, 1);

      // Insert another pending item
      await service.insertPendingImport(_makeCompanion(
        id: 'count-test-2',
        status: TransactionProposalStatus.pending,
      ));

      final count2 = await service.watchPendingCount().first;
      expect(count2, 2);

      // Confirm one — count should decrease
      await service.updatePendingImportStatus(
        'count-test-1',
        TransactionProposalStatus.confirmed,
      );

      final count3 = await service.watchPendingCount().first;
      expect(count3, 1);

      // Insert a non-pending item — should not affect pending count
      await service.insertPendingImport(_makeCompanion(
        id: 'count-test-3',
        status: TransactionProposalStatus.rejected,
      ));

      final count4 = await service.watchPendingCount().first;
      expect(count4, 1);
    });

    test('findByBankRef returns the correct row', () async {
      await service.insertPendingImport(_makeCompanion(
        id: 'ref-test-1',
        bankRef: 'UNIQUE-REF-999',
      ));
      await service.insertPendingImport(_makeCompanion(
        id: 'ref-test-2',
        bankRef: 'OTHER-REF-888',
      ));

      final found = await service.findByBankRef('UNIQUE-REF-999');
      expect(found, isNotNull);
      expect(found!.id, 'ref-test-1');
      expect(found.bankRef, 'UNIQUE-REF-999');
    });

    test('findByBankRef returns null when not found', () async {
      await service.insertPendingImport(_makeCompanion(
        id: 'ref-test-3',
        bankRef: 'SOME-REF',
      ));

      final found = await service.findByBankRef('NONEXISTENT-REF');
      expect(found, isNull);
    });

    test('deleteOldRejected removes old rejected rows', () async {
      // Insert a rejected row with old createdAt
      // We need to insert directly with a custom createdAt
      await service.insertPendingImport(PendingImportsCompanion(
        id: const Value('old-rejected-1'),
        amount: const Value(100.0),
        currencyId: const Value('VES'),
        date: Value(DateTime(2026, 1, 1)),
        type: const Value('E'),
        rawText: const Value('old rejected test'),
        channel: const Value('sms'),
        status: const Value('rejected'),
        createdAt: Value(DateTime(2026, 1, 1)), // 3+ months old
      ));

      // Insert a recent rejected row
      await service.insertPendingImport(PendingImportsCompanion(
        id: const Value('recent-rejected-1'),
        amount: const Value(200.0),
        currencyId: const Value('VES'),
        date: Value(DateTime(2026, 4, 14)),
        type: const Value('E'),
        rawText: const Value('recent rejected test'),
        channel: const Value('sms'),
        status: const Value('rejected'),
        createdAt: Value(DateTime.now()), // just now
      ));

      // Insert a pending row (should not be deleted)
      await service.insertPendingImport(_makeCompanion(
        id: 'pending-keep-1',
        status: TransactionProposalStatus.pending,
      ));

      final deleted = await service.deleteOldRejected(
        olderThan: const Duration(days: 30),
      );
      expect(deleted, 1);

      final remaining = await service.getPendingImports().first;
      expect(remaining, hasLength(2));
      expect(
        remaining.map((r) => r.id).toSet(),
        containsAll(['recent-rejected-1', 'pending-keep-1']),
      );
    });
  });
}
