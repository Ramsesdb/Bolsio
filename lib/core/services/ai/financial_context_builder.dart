import 'package:intl/intl.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/budget/budget_service.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';

class FinancialContextBuilder {
  static final instance = FinancialContextBuilder._();
  FinancialContextBuilder._();

  static const int _maxContextChars = 8000;

  Future<String> buildContext() async {
    try {
      final results = await Future.wait([
        AccountService.instance.getAccounts().first,
        TransactionService.instance.getTransactions(limit: 60).first,
        CategoryService.instance.getCategories().first,
        BudgetServive.instance.getBudgets().first,
      ]);

      final accounts = results[0] as List<dynamic>;
      var transactions = List<dynamic>.from(results[1] as List<dynamic>);
      final categories = (results[2] as List<dynamic>)
          .where((c) => c.type.isExpense)
          .toList();
      final budgets = (results[3] as List<dynamic>)
          .where((b) => b.isActive)
          .toList();

      // Fetch balances for each account
      final balances = <String, double>{};
      for (final account in accounts) {
        try {
          final balance = await AccountService.instance
              .getAccountMoney(account: account, convertToPreferredCurrency: false)
              .first
              .timeout(const Duration(seconds: 3), onTimeout: () => 0.0);
          balances[account.name as String] = balance;
        } catch (_) {
          balances[account.name as String] = 0.0;
        }
      }

      String context = _buildPrompt(
        accounts: accounts,
        balances: balances,
        transactions: transactions,
        categories: categories,
        budgets: budgets,
      );

      while (context.length > _maxContextChars && transactions.isNotEmpty) {
        transactions = transactions.sublist(0, transactions.length - 1);
        context = _buildPrompt(
          accounts: accounts,
          balances: balances,
          transactions: transactions,
          categories: categories,
          budgets: budgets,
        );
      }

      return context;
    } catch (_) {
      return 'Contexto financiero no disponible.';
    }
  }

  String _buildPrompt({
    required List<dynamic> accounts,
    required Map<String, double> balances,
    required List<dynamic> transactions,
    required List<dynamic> categories,
    required List<dynamic> budgets,
  }) {
    final txDateFormat = DateFormat('yyyy-MM-dd');

    final accountsText = accounts.map((a) {
      final bal = balances[a.name as String] ?? 0.0;
      return '- ${a.name}: ${bal.toStringAsFixed(2)} ${a.currency.code}';
    }).join('\n');

    final categoriesText = categories
        .map((c) => '- ${c.id}: ${c.name}')
        .join('\n');

    final budgetsText = budgets.map((b) {
      final range = b.currentDateRange;
      return '- ${b.name}: limite ${b.limitAmount.toStringAsFixed(2)} '
          '${b.trFilters.transactionTypes?.isNotEmpty == true ? '' : ''}'
          '(${DateFormat('yyyy-MM-dd').format(range.start)} -> '
          '${DateFormat('yyyy-MM-dd').format(range.end)})';
    }).join('\n');

    final transactionsText = transactions.map((tx) {
      final category = tx.category?.name ?? 'Sin categoria';
      final desc = <String>[
        if (tx.title != null && (tx.title as String).isNotEmpty) tx.title as String,
        if (tx.notes != null && (tx.notes as String).isNotEmpty) tx.notes as String,
      ].join(' - ');
      return '- ${txDateFormat.format(tx.date)} | ${tx.type.databaseValue} | '
          '${tx.value.toStringAsFixed(2)} ${tx.account.currency.code} | '
          '$category | ${desc.isEmpty ? '-' : desc}';
    }).join('\n');

    return 'Respondes en ESPANOL siempre. Sin markdown innecesario.\n\n'
        'Contexto financiero del usuario:\n'
        'Cuentas:\n${accountsText.isEmpty ? '- Sin cuentas' : accountsText}\n\n'
        'Categorias de gasto:\n${categoriesText.isEmpty ? '- Sin categorias' : categoriesText}\n\n'
        'Presupuestos activos:\n${budgetsText.isEmpty ? '- Sin presupuestos activos' : budgetsText}\n\n'
        'Ultimas transacciones (max 60):\n'
        '${transactionsText.isEmpty ? '- Sin transacciones' : transactionsText}';
  }
}
