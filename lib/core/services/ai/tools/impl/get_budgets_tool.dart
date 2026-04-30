import 'package:bolsio/core/database/services/budget/budget_service.dart';

import '../ai_tool.dart';

class GetBudgetsTool implements AiTool {
  final BudgetServive _budgetService;

  GetBudgetsTool({BudgetServive? budgetService})
      : _budgetService = budgetService ?? BudgetServive.instance;

  @override
  String get name => 'get_budgets';

  @override
  String get description =>
      'Lista los presupuestos del usuario con su limite, valor consumido y '
      'porcentaje usado. Por defecto solo los activos.';

  @override
  bool get isMutating => false;

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'includeInactive': {
            'type': 'boolean',
            'description':
                'Si true, incluye presupuestos pasados o futuros. Default false.',
            'default': false,
          },
        },
        'additionalProperties': false,
      };

  @override
  Future<AiToolResult> execute(Map<String, dynamic> args) async {
    final includeInactive = (args['includeInactive'] as bool?) ?? false;

    final budgets = await _budgetService.getBudgets().first;
    final filtered = includeInactive
        ? budgets
        : budgets.where((b) => b.isActive).toList();

    final items = <Map<String, dynamic>>[];
    for (final budget in filtered) {
      final used = await budget.currentValue.first;
      final range = budget.currentDateRange;
      items.add({
        'id': budget.id,
        'name': budget.name,
        'limit': budget.limitAmount,
        'used': used,
        'remaining': budget.limitAmount - used,
        'percentUsed': budget.limitAmount == 0
            ? 0.0
            : (used / budget.limitAmount) * 100,
        'fromDate': range.start.toIso8601String(),
        'toDate': range.end.toIso8601String(),
        'isActive': budget.isActive,
      });
    }

    return AiToolResult.ok({
      'count': items.length,
      'budgets': items,
    });
  }
}
