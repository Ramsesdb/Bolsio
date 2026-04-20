import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

import '../ai_tool.dart';

class GetStatsByCategoryTool implements AiTool {
  final CategoryService _categoryService;
  final TransactionService _transactionService;

  GetStatsByCategoryTool({
    CategoryService? categoryService,
    TransactionService? transactionService,
  })  : _categoryService = categoryService ?? CategoryService.instance,
        _transactionService =
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

    final categories = await _categoryService
        .getCategories(
          predicate: (c, pc) =>
              c.type.equals(txType == TransactionType.income ? 'I' : 'E'),
        )
        .first;

    final results = <Map<String, dynamic>>[];
    double total = 0.0;

    for (final category in categories) {
      final amount = await _transactionService
          .getTransactionsValueBalance(
            filters: TransactionFilterSet(
              minDate: fromDate,
              maxDate: toDate,
              categoriesIds: [category.id],
              transactionTypes: [txType],
            ),
          )
          .first;
      final absAmount = amount.abs();
      if (absAmount == 0) continue;
      results.add({
        'categoryId': category.id,
        'categoryName': category.name,
        'amount': absAmount,
      });
      total += absAmount;
    }

    results.sort(
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
