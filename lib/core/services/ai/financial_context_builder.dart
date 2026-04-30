import 'package:bolsio/core/database/services/account/account_service.dart';
import 'package:bolsio/core/database/services/category/category_service.dart';

/// Builds a small bootstrap summary (~1k chars) for the assistant's system
/// prompt. Lists what the user HAS (account names + currencies, expense
/// category names/ids) but NO amounts and NO recent transactions — fresh
/// figures come from AI tool calls (`get_balance`, `list_transactions`, etc.).
///
/// Rationale: halves system-prompt tokens, eliminates staleness, steers the
/// model toward tool use rather than reasoning over baked-in snapshots.
class FinancialContextBuilder {
  static final instance = FinancialContextBuilder._();
  FinancialContextBuilder._();

  static const int _maxContextChars = 1200;

  Future<String> buildContext() async {
    try {
      final results = await Future.wait([
        AccountService.instance.getAccounts().first,
        CategoryService.instance.getCategories().first,
      ]);

      final accounts = results[0] as List<dynamic>;
      final allCategories = results[1] as List<dynamic>;
      final expenseCategories =
          allCategories.where((c) => c.type.isExpense).toList();
      final incomeCategories =
          allCategories.where((c) => c.type.isIncome).toList();

      final accountsText = accounts.isEmpty
          ? '- (sin cuentas)'
          : accounts
              .map((a) => '- ${a.id}: ${a.name} (${a.currency.code})')
              .join('\n');

      final expenseCatsText = expenseCategories.isEmpty
          ? '- (sin categorias)'
          : expenseCategories
              .map((c) => '- ${c.id}: ${c.name}')
              .join('\n');

      final incomeCatsText = incomeCategories.isEmpty
          ? '- (sin categorias)'
          : incomeCategories
              .map((c) => '- ${c.id}: ${c.name}')
              .join('\n');

      var ctx = _compose(
        accountsText: accountsText,
        expenseCatsText: expenseCatsText,
        incomeCatsText: incomeCatsText,
      );

      if (ctx.length > _maxContextChars) {
        ctx = ctx.substring(0, _maxContextChars);
      }
      return ctx;
    } catch (_) {
      return 'Contexto financiero no disponible. Usa las tools para consultar datos.';
    }
  }

  String _compose({
    required String accountsText,
    required String expenseCatsText,
    required String incomeCatsText,
  }) {
    return 'Responde SIEMPRE en espanol. Usa las tools disponibles para obtener '
        'saldos, transacciones, estadisticas y presupuestos — nunca inventes '
        'montos ni fechas. Si falta un dato, llama la tool correspondiente.\n\n'
        'Cuentas del usuario:\n$accountsText\n\n'
        'Categorias de gasto:\n$expenseCatsText\n\n'
        'Categorias de ingreso:\n$incomeCatsText';
  }
}
