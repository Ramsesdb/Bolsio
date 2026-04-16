import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallex/app/transactions/auto_import/widgets/pending_import_tile.dart';
import 'package:wallex/core/database/app_db.dart';

/// Helper to build a [PendingImportInDB] directly (no database needed).
PendingImportInDB _makePendingImport({
  required String id,
  double amount = 23500.0,
  String currencyId = 'VES',
  String type = 'E',
  String rawText = 'Realizaste un PagomovilBDV por Bs. 23.500,00',
  String channel = 'sms',
  double confidence = 0.95,
  String? bankRef,
  String? sender,
  String? counterpartyName,
  String status = 'pending',
  String? accountId,
}) {
  return PendingImportInDB(
    id: id,
    accountId: accountId,
    amount: amount,
    currencyId: currencyId,
    date: DateTime(2026, 4, 15, 10, 30),
    type: type,
    counterpartyName: counterpartyName,
    bankRef: bankRef,
    rawText: rawText,
    channel: channel,
    sender: sender,
    confidence: confidence,
    status: status,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('PendingImportTile widget', () {
    testWidgets('displays correct title for income', (tester) async {
      final item = _makePendingImport(
        id: 'test-income-1',
        amount: 277000.0,
        currencyId: 'VES',
        type: 'I',
        counterpartyName: '0414-1234567',
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingImportTile(pendingImport: item),
          ),
        ),
      );

      // Should display "Recibiste" for income
      expect(find.textContaining('Recibiste'), findsOneWidget);
      // Should display counterparty
      expect(find.textContaining('0414-1234567'), findsOneWidget);
    });

    testWidgets('displays correct title for expense', (tester) async {
      final item = _makePendingImport(
        id: 'test-expense-1',
        amount: 300.0,
        currencyId: 'USD',
        type: 'E',
        counterpartyName: 'Amazon',
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingImportTile(pendingImport: item),
          ),
        ),
      );

      expect(find.textContaining('Pagaste'), findsOneWidget);
    });

    testWidgets('shows correct status chips for different statuses',
        (tester) async {
      final items = [
        _makePendingImport(id: 'p1', status: 'pending'),
        _makePendingImport(id: 'p2', status: 'duplicate'),
        _makePendingImport(id: 'p3', status: 'confirmed'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: items
                  .map((item) => PendingImportTile(pendingImport: item))
                  .toList(),
            ),
          ),
        ),
      );

      // Verify all 3 tiles are shown
      expect(find.byType(PendingImportTile), findsNWidgets(3));

      // Verify status chip texts
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Posible duplicado'), findsOneWidget);
      expect(find.text('Confirmado'), findsOneWidget);
    });

    testWidgets('shows "Sin contraparte" when counterparty is null',
        (tester) async {
      final item = _makePendingImport(
        id: 'test-no-counterparty',
        counterpartyName: null,
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingImportTile(pendingImport: item),
          ),
        ),
      );

      expect(find.textContaining('Sin contraparte'), findsOneWidget);
    });

    testWidgets('displays VES amount formatted correctly', (tester) async {
      final item = _makePendingImport(
        id: 'test-ves',
        amount: 1234567.89,
        currencyId: 'VES',
        type: 'E',
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingImportTile(pendingImport: item),
          ),
        ),
      );

      expect(find.textContaining('Bs.'), findsOneWidget);
    });

    testWidgets('displays USD amount formatted correctly', (tester) async {
      final item = _makePendingImport(
        id: 'test-usd',
        amount: 150.50,
        currencyId: 'USD',
        type: 'I',
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingImportTile(pendingImport: item),
          ),
        ),
      );

      expect(find.textContaining('\$'), findsOneWidget);
    });

    testWidgets('displays correct channel icon for SMS', (tester) async {
      final item = _makePendingImport(
        id: 'test-sms',
        channel: 'sms',
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingImportTile(pendingImport: item),
          ),
        ),
      );

      // Should find the SMS icon
      expect(find.byIcon(Icons.sms_outlined), findsOneWidget);
    });

    testWidgets('displays correct channel icon for API', (tester) async {
      final item = _makePendingImport(
        id: 'test-api',
        channel: 'api',
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendingImportTile(pendingImport: item),
          ),
        ),
      );

      expect(find.byIcon(Icons.sync), findsOneWidget);
    });
  });
}
