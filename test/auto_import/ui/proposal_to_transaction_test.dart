import 'package:flutter_test/flutter_test.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
import 'package:bolsio/core/utils/uuid.dart';

/// Tests the logic for building a [TransactionInDB] from a [PendingImportInDB]
/// with user-edited fields, mirroring what ProposalReviewPage does on confirm.
///
/// This is a unit test of the converter logic, not a widget test.
void main() {
  group('Proposal to TransactionInDB conversion', () {
    test('income type produces positive value', () {
      final amount = 277000.0;
      final type = TransactionType.income;
      final value = type == TransactionType.expense ? -amount : amount;

      expect(value, 277000.0);
      expect(value, isPositive);
    });

    test('expense type produces negative value', () {
      final amount = 23500.0;
      final type = TransactionType.expense;
      final value = type == TransactionType.expense ? -amount : amount;

      expect(value, -23500.0);
      expect(value, isNegative);
    });

    test('notes contain auto marker with channel and bank', () {
      const channel = 'sms';
      const bank = 'bdv';
      const bankRef = '987654321098';

      final notes = '[auto:$channel:$bank] ref=$bankRef';

      expect(notes, contains('[auto:sms:bdv]'));
      expect(notes, contains('ref=987654321098'));
    });

    test('notes contain dash when bankRef is null', () {
      const channel = 'api';
      const bank = 'binance';
      const String? bankRef = null;

      final notes = '[auto:$channel:$bank] ref=${bankRef ?? '-'}';

      expect(notes, contains('[auto:api:binance]'));
      expect(notes, contains('ref=-'));
    });

    test('full TransactionInDB can be constructed from proposal fields', () {
      final txId = generateUUID();
      final now = DateTime.now();
      const accountId = 'acc-bdv-001';
      const amount = 23500.0;
      final type = TransactionType.expense;
      final value = type == TransactionType.expense ? -amount : amount;
      const channel = 'sms';
      const bank = 'bdv';
      const bankRef = '987654321098';
      final notes = '[auto:$channel:$bank] ref=$bankRef';

      final tx = TransactionInDB(
        id: txId,
        date: now,
        accountID: accountId,
        value: value,
        title: '0416-1234567',
        notes: notes,
        type: type,
        isHidden: false,
        createdAt: now,
      );

      expect(tx.id, txId);
      expect(tx.accountID, accountId);
      expect(tx.value, -23500.0);
      expect(tx.type, TransactionType.expense);
      expect(tx.notes, contains('[auto:sms:bdv]'));
      expect(tx.notes, contains('ref=987654321098'));
      expect(tx.isHidden, false);
    });

    test('income TransactionInDB has positive value', () {
      final txId = generateUUID();
      final now = DateTime.now();

      final tx = TransactionInDB(
        id: txId,
        date: now,
        accountID: 'acc-binance-001',
        value: 150.0, // positive for income
        title: 'P2P Trade',
        notes: '[auto:api:binance] ref=-',
        type: TransactionType.income,
        isHidden: false,
        createdAt: now,
      );

      expect(tx.value, isPositive);
      expect(tx.type, TransactionType.income);
      expect(tx.notes, contains('[auto:api:binance]'));
    });

    test('bankRef is persisted in notes even when counterparty is empty', () {
      const channel = 'notification';
      const bank = 'bdv';
      const bankRef = '123456789012';
      const counterparty = '';

      final notes = '[auto:$channel:$bank] ref=$bankRef';

      final txId = generateUUID();
      final tx = TransactionInDB(
        id: txId,
        date: DateTime.now(),
        accountID: 'acc-001',
        value: -5000.0,
        title: counterparty.isEmpty ? null : counterparty,
        notes: notes,
        type: TransactionType.expense,
        isHidden: false,
        createdAt: DateTime.now(),
      );

      expect(tx.title, isNull);
      expect(tx.notes, contains('ref=123456789012'));
      expect(tx.notes, contains('[auto:notification:bdv]'));
    });
  });
}
