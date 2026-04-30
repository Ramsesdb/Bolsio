import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

import '../ai_tool.dart';

class ListTransactionsTool implements AiTool {
  final TransactionService _transactionService;

  ListTransactionsTool({TransactionService? transactionService})
      : _transactionService = transactionService ?? TransactionService.instance;

  @override
  String get name => 'list_transactions';

  @override
  String get description =>
      'Lista transacciones del usuario filtradas por rango de fechas, cuentas, '
      'categorias y tipo. Ordenadas por fecha descendente. Limite por defecto 50.';

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
          'accountIds': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'IDs de cuenta a incluir (vacio = todas).',
          },
          'categoryIds': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'IDs de categoria a incluir (vacio = todas).',
          },
          'type': {
            'type': 'string',
            'enum': ['income', 'expense', 'transfer'],
            'description': 'Tipo de transaccion a filtrar.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Maximo de resultados (por defecto 50, maximo 200).',
            'default': 50,
          },
        },
        'additionalProperties': false,
      };

  @override
  Future<AiToolResult> execute(Map<String, dynamic> args) async {
    DateTime? fromDate;
    DateTime? toDate;
    try {
      if (args['fromDate'] is String) {
        fromDate = DateTime.parse(args['fromDate'] as String);
      }
      if (args['toDate'] is String) {
        toDate = DateTime.parse(args['toDate'] as String);
      }
    } catch (_) {
      return AiToolResult.error(
        'Invalid date format. Use ISO 8601 YYYY-MM-DD.',
        code: 'invalid_date',
      );
    }

    final accountIds = (args['accountIds'] as List?)?.cast<String>();
    final categoryIds = (args['categoryIds'] as List?)?.cast<String>();

    List<TransactionType>? types;
    final typeArg = args['type'] as String?;
    if (typeArg != null) {
      switch (typeArg) {
        case 'income':
          types = [TransactionType.income];
          break;
        case 'expense':
          types = [TransactionType.expense];
          break;
        case 'transfer':
          types = [TransactionType.transfer];
          break;
        default:
          return AiToolResult.error(
            'Invalid type "$typeArg". Expected income|expense|transfer.',
            code: 'invalid_type',
          );
      }
    }

    final rawLimit = (args['limit'] as num?)?.toInt() ?? 50;
    final limit = rawLimit.clamp(1, 200);

    final filters = TransactionFilterSet(
      minDate: fromDate,
      maxDate: toDate,
      accountsIDs: accountIds,
      categoriesIds: categoryIds,
      transactionTypes: types,
    );

    final transactions = await _transactionService
        .getTransactions(filters: filters, limit: limit)
        .first;

    final items = transactions
        .map((tx) => <String, dynamic>{
              'id': tx.id,
              'date': tx.date.toIso8601String(),
              'type': tx.type.databaseValue,
              'value': tx.value,
              'currency': tx.account.currency.code,
              'accountId': tx.account.id,
              'accountName': tx.account.name,
              'categoryId': tx.category?.id,
              'categoryName': tx.category?.name,
              'title': tx.title,
              'notes': tx.notes,
            })
        .toList();

    return AiToolResult.ok({
      'count': items.length,
      'limit': limit,
      'transactions': items,
    });
  }
}
