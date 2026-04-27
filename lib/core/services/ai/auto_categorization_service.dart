import 'dart:convert';

import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/auto_import/transaction_proposal.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/services/ai/ai_service.dart';

class AutoCategorySuggestion {
  final String categoryId;
  final double confidence;

  const AutoCategorySuggestion({
    required this.categoryId,
    required this.confidence,
  });
}

class AutoCategorizationService {
  static final instance = AutoCategorizationService._();
  AutoCategorizationService._();

  Future<AutoCategorySuggestion?> suggest({
    required TransactionProposal proposal,
  }) async {
    if (proposal.type == TransactionType.transfer) return null;

    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
    final featureEnabled =
        appStateSettings[SettingKey.aiCategorizationEnabled] == '1';

    if (!aiEnabled || !featureEnabled) return null;

    try {
      final categories = await CategoryService.instance.getCategories().first;
      final allowed = categories
          .where((c) => c.type.matchWithTransactionType(proposal.type))
          .toList();

      if (allowed.isEmpty) return null;

      final allowedMap = {for (final c in allowed) c.id: c};
      final categoriesPrompt = allowed
          .map((c) => '- ${c.id}: ${c.name}')
          .join('\n');

      final raw = await AiService.instance.complete(
        temperature: 0.1,
        messages: [
          {
            'role': 'system',
            'content':
                'Respondes en ESPANOL siempre. Sin markdown innecesario. '
                'Debes responder SOLO con JSON valido con la forma '
                '{"categoryId":"...","confidence":0.0}. '
                'No agregues texto adicional.'
          },
          {
            'role': 'user',
            'content':
                'Clasifica este movimiento usando SOLO una categoria valida.\n'
                'Tipo: ${proposal.type.databaseValue}\n'
                'Monto: ${proposal.amount} ${proposal.currencyId}\n'
                'Counterparty: ${proposal.counterpartyName ?? '-'}\n'
                'Sender: ${proposal.sender ?? '-'}\n'
                'Texto crudo: ${proposal.rawText}\n\n'
                'Categorias permitidas:\n$categoriesPrompt'
          },
        ],
      );

      if (raw == null || raw.isEmpty) return null;

      final jsonText = _extractJsonObject(raw);
      if (jsonText == null) return null;

      final parsed = jsonDecode(jsonText);
      if (parsed is! Map<String, dynamic>) return null;

      final categoryId = parsed['categoryId'];
      final confidenceRaw = parsed['confidence'];

      if (categoryId is! String || !allowedMap.containsKey(categoryId)) {
        return null;
      }

      final confidence = confidenceRaw is num
          ? confidenceRaw.toDouble()
          : double.tryParse(confidenceRaw?.toString() ?? '') ?? 0.0;

      return AutoCategorySuggestion(
        categoryId: categoryId,
        confidence: confidence.clamp(0.0, 1.0),
      );
    } catch (_) {
      return null;
    }
  }

  String? _extractJsonObject(String text) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    return match?.group(0);
  }
}
