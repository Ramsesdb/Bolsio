import 'package:bolsio/core/database/services/account/account_service.dart';

import '../ai_tool.dart';

class GetBalanceTool implements AiTool {
  final AccountService _accountService;

  GetBalanceTool({AccountService? accountService})
      : _accountService = accountService ?? AccountService.instance;

  @override
  String get name => 'get_balance';

  @override
  String get description =>
      'Devuelve el saldo actual de una cuenta por id, o el saldo total de todas '
      'las cuentas cuando no se pasa accountId.';

  @override
  bool get isMutating => false;

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'accountId': {
            'type': 'string',
            'description':
                'ID de la cuenta a consultar. Omite el campo para sumar todas las cuentas.',
          },
          'convertToPreferredCurrency': {
            'type': 'boolean',
            'description':
                'Si true, convierte el saldo a la moneda preferida del usuario.',
            'default': true,
          },
        },
        'additionalProperties': false,
      };

  @override
  Future<AiToolResult> execute(Map<String, dynamic> args) async {
    final accountId = args['accountId'] as String?;
    final convert = (args['convertToPreferredCurrency'] as bool?) ?? true;

    final accounts = await _accountService.getAccounts().first;
    if (accounts.isEmpty) {
      return AiToolResult.ok({
        'accounts': <Map<String, dynamic>>[],
        'total': 0.0,
      });
    }

    if (accountId != null) {
      final matches = accounts.where((a) => a.id == accountId).toList();
      if (matches.isEmpty) {
        return AiToolResult.error(
          'Account not found: $accountId',
          code: 'account_not_found',
        );
      }
      final account = matches.first;
      final balance = await _accountService
          .getAccountMoney(
            account: account,
            convertToPreferredCurrency: convert,
          )
          .first;
      return AiToolResult.ok({
        'accountId': account.id,
        'name': account.name,
        'currency': account.currency.code,
        'balance': balance,
      });
    }

    final entries = <Map<String, dynamic>>[];
    double total = 0.0;
    for (final account in accounts) {
      final balance = await _accountService
          .getAccountMoney(
            account: account,
            convertToPreferredCurrency: convert,
          )
          .first;
      entries.add({
        'accountId': account.id,
        'name': account.name,
        'currency': account.currency.code,
        'balance': balance,
      });
      total += balance;
    }

    return AiToolResult.ok({
      'accounts': entries,
      'total': total,
      'convertedToPreferredCurrency': convert,
    });
  }
}
