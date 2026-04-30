import 'dart:convert';

import 'package:bolsio/core/models/auto_import/capture_channel.dart';
import 'package:bolsio/core/models/auto_import/raw_capture_event.dart';
import 'package:bolsio/core/models/auto_import/transaction_proposal.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
import 'package:bolsio/core/services/ai/ai_service.dart';
import 'package:bolsio/core/services/auto_import/supported_banks.dart';

import 'bank_profile.dart';

/// Generic LLM-based bank profile used as a fallback when no regex profile
/// matches a notification from a known bank sender.
///
/// Sends the raw notification text to the Nexus AI service and attempts to
/// extract a [TransactionProposal] from the structured JSON response.
///
/// This profile is never registered in [bankProfilesRegistry] — it is called
/// directly by the [CaptureOrchestrator] after the normal profile loop fails.
class GenericLlmProfile implements BankProfile {
  const GenericLlmProfile({this.completeOverride});

  /// For tests: allows injecting a mock LLM completion function.
  final Future<String?> Function(String systemPrompt, String userPrompt)?
      completeOverride;

  @override
  String get profileId => 'generic_llm';

  @override
  String get bankName => 'Parser Genérico (IA)';

  /// Not used — the orchestrator uses [resolvedBankName] from [ParseResult].
  @override
  String get accountMatchName => '';

  @override
  CaptureChannel get channel => CaptureChannel.notification;

  /// Not used — the orchestrator calls this profile directly after the loop.
  @override
  List<String> get knownSenders => const [];

  @override
  int get profileVersion => 1;

  static const String _systemPrompt = '''
Eres un extractor de datos de transacciones bancarias. Recibes el texto de una notificación push o SMS de un banco y debes retornar SOLO JSON válido sin markdown ni explicaciones.

Si el texto NO contiene una transacción monetaria (es un OTP, código de verificación, promoción, o mensaje informativo), retorna:
{"isTransaction":false}

Si SÍ contiene una transacción monetaria, retorna:
{"isTransaction":true,"amount":number,"currencyCode":"VES" o "USD" u otro ISO 4217,"type":"income" o "expense","counterpartyName":string o null,"bankRef":string o null,"bankName":string,"date":"YYYY-MM-DD" o null,"confidence":number}

Reglas:
- amount: siempre positivo, sin signo
- currencyCode: infiere del contexto (Bs. = VES, \$ = USD)
- type: "income" si recibes dinero, "expense" si lo envías o pagas
- bankRef: número de referencia, operación, o transacción si aparece
- date: fecha de la transacción en formato YYYY-MM-DD, null si no aparece
- confidence: tu confianza en la extracción, entre 0.0 y 1.0
''';

  @override
  Future<TransactionProposal?> tryParse(
    RawCaptureEvent event, {
    required String? accountId,
  }) async {
    final result = await tryParseWithDetails(event, accountId: accountId);
    return result.success ? result.transaction : null;
  }

  @override
  Future<ParseResult> tryParseWithDetails(
    RawCaptureEvent event, {
    required String? accountId,
  }) async {
    final senderHint =
        kPackageToDisplayName[event.sender] ?? event.sender;
    final userPrompt =
        'Banco: $senderHint\nFecha recepción: ${event.receivedAt.toIso8601String()}\nTexto: ${event.rawText}';

    String? rawJson;
    try {
      if (completeOverride != null) {
        rawJson = await completeOverride!(_systemPrompt, userPrompt);
      } else {
        rawJson = await AiService.instance
            .complete(
              messages: [
                {'role': 'system', 'content': _systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
              temperature: 0.1,
              maxTokens: 256,
            )
            .timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      return ParseResult.failed('llm_unavailable: $e');
    }

    if (rawJson == null || rawJson.isEmpty) {
      return ParseResult.failed('llm_unavailable');
    }

    // Strip markdown code fences if present (some models wrap output in ```json)
    var cleaned = rawJson.trim();
    if (cleaned.startsWith('```')) {
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline != -1) {
        cleaned = cleaned.substring(firstNewline + 1);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trimRight();
      }
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      return ParseResult.failed('llm_invalid_response: $e');
    }

    if (json['isTransaction'] != true) {
      return ParseResult.failed('no es transacción');
    }

    final amount = (json['amount'] as num?)?.toDouble();
    if (amount == null || amount <= 0) {
      return ParseResult.failed('amount inválido');
    }

    final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    if (confidence < 0.4) {
      return ParseResult.failed('confianza muy baja ($confidence)');
    }

    final currencyCode =
        (json['currencyCode'] as String?)?.toUpperCase() ?? 'VES';
    final typeStr = json['type'] as String?;
    final txType =
        typeStr == 'income' ? TransactionType.income : TransactionType.expense;
    final bankName = (json['bankName'] as String?) ?? senderHint;

    DateTime txDate = event.receivedAt;
    final dateStr = json['date'] as String?;
    if (dateStr != null) {
      try {
        txDate = DateTime.parse(dateStr);
      } catch (_) {}
    }

    final proposal = TransactionProposal.newProposal(
      accountId: accountId,
      amount: amount,
      currencyId: currencyCode,
      date: txDate,
      type: txType,
      counterpartyName: json['counterpartyName'] as String?,
      bankRef: json['bankRef'] as String?,
      rawText: event.rawText,
      channel: event.channel,
      sender: event.sender,
      // Cap at 0.75 to distinguish from regex parsers (which score 0.85–0.95)
      confidence: confidence.clamp(0.0, 0.75),
      parsedBySender: 'generic_llm_v1',
    );

    return ParseResult.parsed(proposal, resolvedBankName: bankName);
  }
}
