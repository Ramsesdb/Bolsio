import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/budget/budget.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:wallex/core/services/ai/ai_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';

class BudgetPredictionResult {
  final String text;
  final bool isFallback;

  const BudgetPredictionResult({
    required this.text,
    this.isFallback = false,
  });
}

class _CachedBudgetPrediction {
  final BudgetPredictionResult result;
  final DateTime createdAt;

  const _CachedBudgetPrediction({
    required this.result,
    required this.createdAt,
  });
}

class BudgetPredictionService {
  static final instance = BudgetPredictionService._();
  BudgetPredictionService._();

  static const _ttl = Duration(hours: 1);
  final Map<String, _CachedBudgetPrediction> _cache = {};

  Future<BudgetPredictionResult?> getPrediction(Budget budget) async {
    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';
    final featureEnabled = appStateSettings[SettingKey.aiBudgetPredictionEnabled] == '1';
    if (!aiEnabled || !featureEnabled) return null;

    final hasKey = await AiService.instance.isConfigured();
    if (!hasKey) return null;

    final now = DateTime.now();
    final cached = _cache[budget.id];
    if (cached != null && now.difference(cached.createdAt) < _ttl) {
      return cached.result;
    }

    final range = budget.currentDateRange;
    final totalDays = (range.end.difference(range.start).inDays + 1).clamp(1, 366);
    final clampedNow = now.isBefore(range.start)
        ? range.start
        : (now.isAfter(range.end) ? range.end : now);
    final daysElapsed = (clampedNow.difference(range.start).inDays + 1).clamp(1, totalDays);
    final daysRemaining = (totalDays - daysElapsed).clamp(0, totalDays);

    final currentSpend = await budget.currentValue.first;

    final history = <double>[];
    for (var i = 1; i <= 3; i++) {
      final previous = budget.periodState.getDates(periodModifier: -i);
      final start = previous.$1;
      final end = previous.$2;
      if (start == null || end == null) continue;

      final amount = await TransactionService.instance
          .getTransactionsValueBalance(
            filters: TransactionFilterSet(
              minDate: start,
              maxDate: end,
              accountsIDs: budget.trFilters.accountsIDs,
              categoriesIds: budget.trFilters.categoriesIds,
              status: budget.trFilters.status,
              transactionTypes: const [TransactionType.expense],
            ),
          )
          .first;

      history.add(amount);
    }

    if (history.where((v) => v > 0).length < 2) {
      final projection = (currentSpend / daysElapsed) * totalDays;
      final pct = budget.limitAmount <= 0
          ? 0.0
          : (projection / budget.limitAmount) * 100;

      final fallback = BudgetPredictionResult(
        text:
            'A tu ritmo actual, usaras el ${pct.toStringAsFixed(0)}% del presupuesto.',
        isFallback: true,
      );

      _cache[budget.id] = _CachedBudgetPrediction(
        result: fallback,
        createdAt: now,
      );
      return fallback;
    }

    final response = await AiService.instance.complete(
      temperature: 0.3,
      messages: [
        {
          'role': 'system',
          'content':
              'Respondes en ESPANOL siempre. Sin markdown innecesario. '
              'Responde en maximo 2 frases con una prediccion de gasto del presupuesto.'
        },
        {
          'role': 'user',
          'content':
              'Predice el consumo del presupuesto ${budget.name}.\n'
              'Limite: ${budget.limitAmount.toStringAsFixed(2)}\n'
              'Gasto actual: ${currentSpend.toStringAsFixed(2)}\n'
              'Dias transcurridos: $daysElapsed\n'
              'Dias restantes: $daysRemaining\n'
              'Historico ultimos periodos: ${history.map((e) => e.toStringAsFixed(2)).join(', ')}'
        },
      ],
    );

    final result = BudgetPredictionResult(
      text: response?.trim().isNotEmpty == true ? response!.trim() : 'IA no disponible',
    );

    _cache[budget.id] = _CachedBudgetPrediction(result: result, createdAt: now);
    return result;
  }
}
