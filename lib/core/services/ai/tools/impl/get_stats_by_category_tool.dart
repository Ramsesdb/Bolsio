import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

import '../ai_tool.dart';

class GetStatsByCategoryTool implements AiTool {
  final TransactionService _transactionService;

  GetStatsByCategoryTool({
    TransactionService? transactionService,
  }) : _transactionService =
            transactionService ?? TransactionService.instance;

  @override
  String get name => 'get_stats_by_category';

  @override
  String get description =>
      'Agrega el gasto o ingreso por categoria en un periodo. Devuelve total '
      'por categoria y total global, convertido a la moneda preferida del usuario.';

  @override
  bool get isMutating => false;

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'fromDate': {
            'type': 'string',
            'description': 'Fecha inicial inclusiva (ISO 8601 YYYY-MM-DD).',
          },
          'toDate': {
            'type': 'string',
            'description': 'Fecha final exclusiva (ISO 8601 YYYY-MM-DD).',
          },
          'type': {
            'type': 'string',
            'enum': ['expense', 'income'],
            'description': 'Tipo de transaccion a agregar (default expense).',
            'default': 'expense',
          },
        },
        'required': ['fromDate', 'toDate'],
        'additionalProperties': false,
      };

  @override
  Future<AiToolResult> execute(Map<String, dynamic> args) async {
    DateTime fromDate;
    DateTime toDate;
    try {
      fromDate = DateTime.parse(args['fromDate'] as String);
      toDate = DateTime.parse(args['toDate'] as String);
    } catch (_) {
      return AiToolResult.error(
        'Invalid or missing date. Use ISO 8601 YYYY-MM-DD for fromDate and toDate.',
        code: 'invalid_date',
      );
    }

    final typeArg = (args['type'] as String?) ?? 'expense';
    final txType = typeArg == 'income'
        ? TransactionType.income
        : TransactionType.expense;

    // Use the same query path as `list_transactions` (no forced stats-status
    // filter) so auto-imported transactions with NULL status are included.
    // Aggregation by category is done here in Dart.
    final transactions = await _transactionService
        .getTransactions(
          filters: TransactionFilterSet(
            minDate: fromDate,
            maxDate: toDate,
            transactionTypes: [txType],
          ),
        )
        .first;

    final perCategory = <String, Map<String, dynamic>>{};
    double total = 0.0;

    for (final tx in transactions) {
      final category = tx.category;
      if (category == null) continue;

      final amount = (tx.currentValueInPreferredCurrency ?? tx.value).abs();
      if (amount == 0) continue;

      final bucket = perCategory.putIfAbsent(
        category.id,
        () => <String, dynamic>{
          'categoryId': category.id,
          'categoryName': category.name,
          'amount': 0.0,
        },
      );
      bucket['amount'] = (bucket['amount'] as double) + amount;
      total += amount;
    }

    final results = perCategory.values.toList()
      ..sort(
        (a, b) => (b['amount'] as double).compareTo(a['amount'] as double),
      );

    return AiToolResult.ok({
      'fromDate': fromDate.toIso8601String(),
      'toDate': toDate.toIso8601String(),
      'type': txType.databaseValue,
      'total': total,
      'categories': results,
    });
  }
}
