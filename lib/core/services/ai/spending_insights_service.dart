import 'dart:async';

import 'package:intl/intl.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:wallex/core/services/ai/ai_service.dart';

class SpendingInsightsResult {
  final String text;
  const SpendingInsightsResult(this.text);
}

class SpendingInsightsService {
  static final instance = SpendingInsightsService._();
  SpendingInsightsService._();

  Completer<SpendingInsightsResult?>? _inFlight;

  Future<SpendingInsightsResult?> generateInsights({
    required DatePeriodState periodState,
  }) async {
    if (_inFlight != null) return _inFlight!.future;

    final completer = Completer<SpendingInsightsResult?>();
    _inFlight = completer;

    try {
      final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
      final featureEnabled = appStateSettings[SettingKey.aiInsightsEnabled] == '1';
      if (!aiEnabled || !featureEnabled) {
        completer.complete(null);
        return completer.future;
      }

      final hasKey = await AiService.instance.isConfigured();
      if (!hasKey) {
        completer.complete(null);
        return completer.future;
      }

      final now = DateTime.now();
      final currentEnd = periodState.endDate ?? now;
      final currentStart = periodState.startDate ?? currentEnd.subtract(const Duration(days: 30));
      final periodDays = currentEnd.difference(currentStart).inDays.abs().clamp(1, 365);
      final previousEnd = currentStart;
      final previousStart = previousEnd.subtract(Duration(days: periodDays));

      final categories = await CategoryService.instance
          .getCategories(predicate: (c, pc) => c.type.equals('E'))
          .first;

      if (categories.isEmpty) {
        completer.complete(const SpendingInsightsResult('No hay categorias de gasto para analizar.'));
        return completer.future;
      }

      final deltas = await Future.wait(categories.map((category) async {
        final currentAmount = await TransactionService.instance
            .getTransactionsValueBalance(
              filters: TransactionFilterSet(
                minDate: currentStart,
                maxDate: currentEnd,
                categoriesIds: [category.id],
                transactionTypes: const [TransactionType.expense],
              ),
            )
            .first;

        final previousAmount = await TransactionService.instance
            .getTransactionsValueBalance(
              filters: TransactionFilterSet(
                minDate: previousStart,
                maxDate: previousEnd,
                categoriesIds: [category.id],
                transactionTypes: const [TransactionType.expense],
              ),
            )
            .first;

        if (currentAmount <= 0) return null;

        final metric = previousAmount == 0
            ? currentAmount.abs()
            : ((currentAmount - previousAmount) / previousAmount).abs();

        final label = previousAmount == 0
            ? 'Nuevo gasto: ${currentAmount.toStringAsFixed(2)} en ${category.name}'
            : '${category.name}: ${currentAmount.toStringAsFixed(2)} vs ${previousAmount.toStringAsFixed(2)} '
                '(${(((currentAmount - previousAmount) / previousAmount) * 100).toStringAsFixed(1)}%)';

        return (metric: metric, label: label);
      }));

      final topDeltas = deltas
          .whereType<({double metric, String label})>()
          .toList()
        ..sort((a, b) => b.metric.compareTo(a.metric));

      final top5 = topDeltas.take(5).toList();

      if (top5.isEmpty) {
        completer.complete(const SpendingInsightsResult('No hay cambios significativos de gasto en el periodo.'));
        return completer.future;
      }

      final formatter = DateFormat('dd/MM/yyyy');
      final payload = top5.map((d) => '- ${d.label}').join('\n');

      final response = await AiService.instance.complete(
        temperature: 0.5,
        messages: [
          {
            'role': 'system',
            'content':
                'Respondes en ESPANOL siempre. Sin markdown innecesario. '
                'Genera 2-3 frases claras y accionables sobre el comportamiento de gasto.'
          },
          {
            'role': 'user',
            'content':
                'Analiza estos cambios de gasto entre periodos:\n'
                'Periodo actual: ${formatter.format(currentStart)} - ${formatter.format(currentEnd)}\n'
                'Periodo anterior: ${formatter.format(previousStart)} - ${formatter.format(previousEnd)}\n'
                '$payload'
          },
        ],
      );

      if (response == null || response.trim().isEmpty) {
        completer.complete(const SpendingInsightsResult('IA no disponible'));
        return completer.future;
      }

      completer.complete(SpendingInsightsResult(response.trim()));
      return completer.future;
    } catch (_) {
      completer.complete(const SpendingInsightsResult('IA no disponible'));
      return completer.future;
    } finally {
      _inFlight = null;
    }
  }
}
