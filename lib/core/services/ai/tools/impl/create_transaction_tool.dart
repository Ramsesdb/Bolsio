import 'package:flutter/foundation.dart';
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
          'currency': {
            'type': 'string',
            'description':
                'Codigo ISO 4217 en mayusculas (USD, VES, EUR, COP). '
                'Completalo SOLO si el usuario menciona la divisa explicitamente '
                '(dolares, bolivares, euros...). Si se omite, se asume la divisa '
                'de la cuenta.',
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
    final matchedById = accountId != null
        ? openAccounts.where((a) => a.id == accountId).toList()
        : const [];

    if (accountId != null && matchedById.isEmpty) {
      return AiToolResult.error(
        'Account not found or closed: $accountId',
        code: 'account_not_found',
      );
    }

    final rawCurrencyArg = args['currency'];
    final voicedCurrencyCode = (rawCurrencyArg is String &&
            rawCurrencyArg.trim().isNotEmpty)
        ? rawCurrencyArg.trim().toUpperCase()
        : null;

    // Currency-aware account fallback: when the LLM didn't pick an account
    // (or picked one whose currency doesn't match the voiced currency), find
    // the first open account whose currency matches what the user said.
    var resolved = matchedById.isNotEmpty
        ? matchedById.first
        : openAccounts.first;
    if (voicedCurrencyCode != null) {
      final currentCode = resolved.currency.code.toUpperCase();
      if (currentCode != voicedCurrencyCode) {
        final match = openAccounts
            .where((a) => a.currency.code.toUpperCase() == voicedCurrencyCode);
        if (match.isNotEmpty) {
          resolved = match.first;
        } else {
          debugPrint(
            'CreateTransactionTool: no open account in currency '
            '"$voicedCurrencyCode"; falling back to "${resolved.name}" '
            '(${resolved.currency.code}).',
          );
        }
      }
    }

    // Date sanitization: LLMs sometimes hallucinate dates from their training
    // data (e.g. 2024-06-07) when the user didn't mention one. We treat any
    // missing / empty / unparseable value as "use now", and if the parsed
    // value is suspiciously far in the past (>7 days old) we also fall back
    // to now — voice capture is always about "right now" expenses.
    final now = DateTime.now();
    DateTime date = now;
    final rawDate = args['date'];
    final dateArg =
        (rawDate is String && rawDate.trim().isNotEmpty) ? rawDate.trim() : null;
    DateTime? parsed;
    if (dateArg != null) {
      parsed = DateTime.tryParse(dateArg);
      if (parsed != null) {
        final lowerBound = now.subtract(const Duration(days: 7));
        if (parsed.isBefore(lowerBound)) {
          debugPrint(
            'CreateTransactionTool: rejecting stale LLM date '
            '"$dateArg" -> $parsed (older than $lowerBound); using now.',
          );
          parsed = null;
        }
      } else {
        debugPrint(
          'CreateTransactionTool: unparseable LLM date "$dateArg"; using now.',
        );
      }
    }
    debugPrint(
      'CreateTransactionTool date arg: $rawDate -> parsed: $parsed '
      '(final: ${parsed ?? now})',
    );
    if (parsed != null) date = parsed;

    final categoryId = args['categoryId'] as String?;
    final title = args['title'] as String?;
    final notes = args['notes'] as String?;

    if (execMode == AiToolExecMode.propose) {
      final proposal = TransactionProposal.newProposal(
        accountId: resolved.id,
        amount: rawAmount,
        currencyId: voicedCurrencyCode ?? resolved.currency.code,
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
