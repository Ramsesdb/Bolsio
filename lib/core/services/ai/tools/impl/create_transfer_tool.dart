import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/utils/uuid.dart';

import '../ai_tool.dart';

/// Tool that creates a transfer between two accounts.
///
/// Commit-only: propose mode is rejected because transfers are more delicate
/// (two accounts, possible FX leg) and always require explicit UI approval
/// from the chat agent's approval bubble.
class CreateTransferTool implements AiTool {
  final AiToolExecMode execMode;
  final AccountService _accountService;
  final TransactionService _transactionService;

  CreateTransferTool({
    this.execMode = AiToolExecMode.commit,
    AccountService? accountService,
    TransactionService? transactionService,
  })  : _accountService = accountService ?? AccountService.instance,
        _transactionService =
            transactionService ?? TransactionService.instance;

  @override
  String get name => 'create_transfer';

  @override
  String get description =>
      'Crea una transferencia entre dos cuentas del usuario. Requiere monto, '
      'cuenta origen y cuenta destino. Si las monedas difieren se debe pasar '
      'valueInDestiny.';

  @override
  bool get isMutating => true;

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'amount': {
            'type': 'number',
            'description':
                'Monto absoluto positivo que sale de la cuenta origen.',
          },
          'fromAccountId': {
            'type': 'string',
            'description': 'ID de la cuenta origen.',
          },
          'toAccountId': {
            'type': 'string',
            'description': 'ID de la cuenta destino.',
          },
          'valueInDestiny': {
            'type': 'number',
            'description':
                'Monto que llega a la cuenta destino, cuando las monedas difieren.',
          },
          'title': {
            'type': 'string',
            'description': 'Titulo corto opcional.',
          },
          'notes': {
            'type': 'string',
            'description': 'Notas extendidas opcionales.',
          },
          'date': {
            'type': 'string',
            'description': 'Fecha ISO 8601; por defecto ahora.',
          },
        },
        'required': ['amount', 'fromAccountId', 'toAccountId'],
        'additionalProperties': false,
      };

  @override
  Future<AiToolResult> execute(Map<String, dynamic> args) async {
    if (execMode == AiToolExecMode.propose) {
      return AiToolResult.error(
        'create_transfer does not support propose mode; use commit.',
        code: 'unsupported_mode',
      );
    }

    final amount = (args['amount'] as num?)?.toDouble();
    if (amount == null || amount <= 0) {
      return AiToolResult.error(
        'amount is required and must be > 0.',
        code: 'invalid_amount',
      );
    }
    final fromAccountId = args['fromAccountId'] as String?;
    final toAccountId = args['toAccountId'] as String?;
    if (fromAccountId == null || toAccountId == null) {
      return AiToolResult.error(
        'fromAccountId and toAccountId are required.',
        code: 'missing_account',
      );
    }
    if (fromAccountId == toAccountId) {
      return AiToolResult.error(
        'fromAccountId must differ from toAccountId.',
        code: 'same_account',
      );
    }

    final accounts = await _accountService.getAccounts().first;
    final fromMatches =
        accounts.where((a) => a.id == fromAccountId).toList();
    final toMatches = accounts.where((a) => a.id == toAccountId).toList();
    if (fromMatches.isEmpty) {
      return AiToolResult.error(
        'from account not found: $fromAccountId',
        code: 'account_not_found',
      );
    }
    if (toMatches.isEmpty) {
      return AiToolResult.error(
        'to account not found: $toAccountId',
        code: 'account_not_found',
      );
    }
    final from = fromMatches.first;
    final to = toMatches.first;

    final valueInDestiny = (args['valueInDestiny'] as num?)?.toDouble() ??
        (from.currency.code == to.currency.code ? amount : null);
    if (from.currency.code != to.currency.code && valueInDestiny == null) {
      return AiToolResult.error(
        'valueInDestiny is required when source and destination currencies differ.',
        code: 'missing_destination_value',
      );
    }

    DateTime date = DateTime.now();
    final dateArg = args['date'] as String?;
    if (dateArg != null) {
      try {
        date = DateTime.parse(dateArg);
      } catch (_) {
        return AiToolResult.error(
          'Invalid date: $dateArg',
          code: 'invalid_date',
        );
      }
    }

    final title = args['title'] as String?;
    final notes = args['notes'] as String?;
    final newId = generateUUID();

    final transfer = TransactionInDB(
      id: newId,
      date: date,
      value: -amount,
      isHidden: false,
      type: TransactionType.transfer,
      accountID: from.id,
      receivingAccountID: to.id,
      valueInDestiny: valueInDestiny,
      status: date.isAfter(DateTime.now())
          ? TransactionStatus.pending
          : TransactionStatus.reconciled,
      title: (title != null && title.isNotEmpty) ? title : null,
      notes: (notes != null && notes.isNotEmpty) ? notes : null,
      createdAt: DateTime.now(),
    );

    await _transactionService.insertTransaction(transfer);

    return AiToolResult.ok({
      'id': newId,
      'fromAccountId': from.id,
      'toAccountId': to.id,
      'amount': amount,
      'valueInDestiny': valueInDestiny,
      'date': date.toIso8601String(),
      'committed': true,
    });
  }
}
