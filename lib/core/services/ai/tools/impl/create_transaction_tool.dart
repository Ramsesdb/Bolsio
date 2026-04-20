import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/models/auto_import/capture_channel.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/utils/uuid.dart';

import '../ai_tool.dart';

/// Tool that creates a single income or expense transaction.
///
/// In [AiToolExecMode.propose] mode (used by quick-expense voice capture),
/// the tool returns a [TransactionProposal] without writing to Drift — the
/// review sheet commits after user confirmation.
///
/// In [AiToolExecMode.commit] mode (used by the chat agent after explicit
/// approval), the tool writes directly via `TransactionService.insertTransaction`.
class CreateTransactionTool implements AiTool {
  final AiToolExecMode execMode;
  final CaptureChannel captureChannel;
  final AccountService _accountService;
  final TransactionService _transactionService;

  CreateTransactionTool({
    this.execMode = AiToolExecMode.propose,
    this.captureChannel = CaptureChannel.voice,
    AccountService? accountService,
    TransactionService? transactionService,
  })  : _accountService = accountService ?? AccountService.instance,
        _transactionService =
            transactionService ?? TransactionService.instance;

  @override
  String get name => 'create_transaction';

  @override
  String get description =>
      'Crea una transaccion de ingreso o gasto. Requiere monto, tipo y cuenta. '
      'El monto es siempre positivo; el signo se aplica segun el tipo.';

  @override
  bool get isMutating => true;

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'amount': {
            'type': 'number',
            'description':
                'Monto absoluto positivo. Para gastos el signo se aplica automaticamente.',
          },
          'type': {
            'type': 'string',
            'enum': ['income', 'expense'],
            'description': 'Tipo de transaccion.',
          },
          'accountId': {
            'type': 'string',
            'description':
                'ID de la cuenta. Si se omite, se usa la primera cuenta abierta.',
          },
          'categoryId': {
            'type': 'string',
            'description':
                'ID de la categoria. Recomendado para gastos; opcional para ingresos.',
          },
          'title': {
            'type': 'string',
            'description': 'Titulo corto de la transaccion.',
          },
          'notes': {
            'type': 'string',
            'description': 'Notas extendidas.',
          },
          'date': {
            'type': 'string',
            'description': 'Fecha ISO 8601; por defecto ahora.',
          },
        },
        'required': ['amount', 'type'],
        'additionalProperties': false,
      };

  @override
  Future<AiToolResult> execute(Map<String, dynamic> args) async {
    final rawAmount = (args['amount'] as num?)?.toDouble();
    if (rawAmount == null || rawAmount <= 0) {
      return AiToolResult.error(
        'amount is required and must be > 0.',
        code: 'invalid_amount',
      );
    }

    final typeArg = args['type'] as String?;
    TransactionType txType;
    switch (typeArg) {
      case 'income':
        txType = TransactionType.income;
        break;
      case 'expense':
        txType = TransactionType.expense;
        break;
      default:
        return AiToolResult.error(
          'type is required: income|expense.',
          code: 'invalid_type',
        );
    }

    final accountId = args['accountId'] as String?;
    final accounts = await _accountService.getAccounts().first;
    final openAccounts =
        accounts.where((a) => a.closingDate == null).toList();
    if (openAccounts.isEmpty) {
      return AiToolResult.error(
        'No open account available.',
        code: 'no_account',
      );
    }
    final account = accountId != null
        ? openAccounts.where((a) => a.id == accountId).toList()
        : <dynamic>[];
    final resolved = account.isNotEmpty ? account.first : openAccounts.first;

    if (accountId != null && account.isEmpty) {
      return AiToolResult.error(
        'Account not found or closed: $accountId',
        code: 'account_not_found',
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

    final categoryId = args['categoryId'] as String?;
    final title = args['title'] as String?;
    final notes = args['notes'] as String?;

    if (execMode == AiToolExecMode.propose) {
      final proposal = TransactionProposal.newProposal(
        accountId: resolved.id,
        amount: rawAmount,
        currencyId: resolved.currency.code,
        date: date,
        type: txType,
        counterpartyName: title,
        rawText: [title, notes].whereType<String>().join(' - '),
        channel: captureChannel,
        confidence: 0.9,
        proposedCategoryId: categoryId,
      );
      return AiToolResult.proposal(proposal);
    }

    final newId = generateUUID();
    final signedValue =
        txType == TransactionType.expense ? -rawAmount : rawAmount;

    final transactionToInsert = TransactionInDB(
      id: newId,
      date: date,
      value: signedValue,
      isHidden: false,
      type: txType,
      accountID: resolved.id,
      categoryID: categoryId,
      status: date.isAfter(DateTime.now())
          ? TransactionStatus.pending
          : TransactionStatus.reconciled,
      title: (title != null && title.isNotEmpty) ? title : null,
      notes: (notes != null && notes.isNotEmpty) ? notes : null,
      createdAt: DateTime.now(),
    );

    await _transactionService.insertTransaction(transactionToInsert);

    return AiToolResult.ok({
      'id': newId,
      'accountId': resolved.id,
      'amount': rawAmount,
      'type': txType.databaseValue,
      'categoryId': categoryId,
      'date': date.toIso8601String(),
      'committed': true,
    });
  }
}
