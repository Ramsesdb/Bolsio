import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal_status.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';

void main() {
  group('TransactionProposal', () {
    test('newProposal() generates a non-empty UUID', () {
      final proposal = TransactionProposal.newProposal(
        amount: 23500.0,
        currencyId: 'VES',
        date: DateTime(2026, 4, 15, 10, 30),
        type: TransactionType.expense,
        rawText: 'Realizaste un PagomovilBDV por Bs. 23.500,00',
        channel: CaptureChannel.sms,
        confidence: 0.95,
      );

      expect(proposal.id, isNotEmpty);
      // UUID v4 format: 8-4-4-4-12 hex chars
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(proposal.id),
        isTrue,
        reason: 'Expected a valid UUID v4, got: ${proposal.id}',
      );
    });

    test('newProposal() two calls generate different UUIDs', () {
      final p1 = TransactionProposal.newProposal(
        amount: 100.0,
        currencyId: 'USD',
        date: DateTime.now(),
        type: TransactionType.income,
        rawText: 'test 1',
        channel: CaptureChannel.notification,
        confidence: 0.8,
      );
      final p2 = TransactionProposal.newProposal(
        amount: 100.0,
        currencyId: 'USD',
        date: DateTime.now(),
        type: TransactionType.income,
        rawText: 'test 2',
        channel: CaptureChannel.notification,
        confidence: 0.8,
      );

      expect(p1.id, isNot(equals(p2.id)));
    });

    test('toCompanion() maps all fields correctly', () {
      final date = DateTime(2026, 4, 15, 14, 0);
      final proposal = TransactionProposal(
        id: 'test-uuid-1234',
        accountId: 'acc-bdv-001',
        amount: 23500.0,
        currencyId: 'VES',
        date: date,
        type: TransactionType.expense,
        counterpartyName: '0416-1234567',
        bankRef: '987654321098',
        rawText: 'Realizaste un PagomovilBDV por Bs. 23.500,00',
        channel: CaptureChannel.sms,
        sender: '2662',
        confidence: 0.95,
        proposedCategoryId: 'cat-transfers',
        dedupeMatched: false,
        parsedBySender: 'bdv_sms',
      );

      final companion = proposal.toCompanion(
        status: TransactionProposalStatus.pending,
      );

      expect(companion.id.value, 'test-uuid-1234');
      expect(companion.accountId.value, 'acc-bdv-001');
      expect(companion.amount.value, 23500.0);
      expect(companion.currencyId.value, 'VES');
      expect(companion.date.value, date);
      expect(companion.type.value, 'E');
      expect(companion.counterpartyName.value, '0416-1234567');
      expect(companion.bankRef.value, '987654321098');
      expect(companion.rawText.value,
          'Realizaste un PagomovilBDV por Bs. 23.500,00');
      expect(companion.channel.value, 'sms');
      expect(companion.sender.value, '2662');
      expect(companion.confidence.value, 0.95);
      expect(companion.proposedCategoryId.value, 'cat-transfers');
      expect(companion.status.value, 'pending');
    });

    test('toCompanion() respects the status argument', () {
      final proposal = TransactionProposal.newProposal(
        amount: 50.0,
        currencyId: 'USD',
        date: DateTime.now(),
        type: TransactionType.income,
        rawText: 'Received 50 USD P2P',
        channel: CaptureChannel.notification,
        confidence: 0.9,
      );

      final pendingCompanion = proposal.toCompanion(
        status: TransactionProposalStatus.pending,
      );
      expect(pendingCompanion.status.value, 'pending');

      final confirmedCompanion = proposal.toCompanion(
        status: TransactionProposalStatus.confirmed,
      );
      expect(confirmedCompanion.status.value, 'confirmed');

      final rejectedCompanion = proposal.toCompanion(
        status: TransactionProposalStatus.rejected,
      );
      expect(rejectedCompanion.status.value, 'rejected');

      final duplicateCompanion = proposal.toCompanion(
        status: TransactionProposalStatus.duplicate,
      );
      expect(duplicateCompanion.status.value, 'duplicate');
    });

    test('toCompanion() maps income type as "I"', () {
      final proposal = TransactionProposal.newProposal(
        amount: 100.0,
        currencyId: 'USD',
        date: DateTime.now(),
        type: TransactionType.income,
        rawText: 'Income test',
        channel: CaptureChannel.notification,
        confidence: 0.8,
      );

      final companion = proposal.toCompanion(
        status: TransactionProposalStatus.pending,
      );
      expect(companion.type.value, 'I');
    });
  });

  group('CaptureChannel enum', () {
    test('dbValue returns correct strings', () {
      expect(CaptureChannel.sms.dbValue, 'sms');
      expect(CaptureChannel.notification.dbValue, 'notification');
    });

    test('fromDbValue round-trips correctly', () {
      for (final channel in CaptureChannel.values) {
        expect(CaptureChannel.fromDbValue(channel.dbValue), channel);
      }
    });

    test('fromDbValue throws on unknown value', () {
      expect(
        () => CaptureChannel.fromDbValue('email'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TransactionProposalStatus enum', () {
    test('dbValue returns correct strings', () {
      expect(TransactionProposalStatus.pending.dbValue, 'pending');
      expect(TransactionProposalStatus.confirmed.dbValue, 'confirmed');
      expect(TransactionProposalStatus.rejected.dbValue, 'rejected');
      expect(TransactionProposalStatus.duplicate.dbValue, 'duplicate');
    });

    test('fromDbValue round-trips correctly', () {
      for (final status in TransactionProposalStatus.values) {
        expect(TransactionProposalStatus.fromDbValue(status.dbValue), status);
      }
    });

    test('fromDbValue throws on unknown value', () {
      expect(
        () => TransactionProposalStatus.fromDbValue('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
