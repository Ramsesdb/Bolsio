import 'package:kilatex/core/database/services/transaction/transaction_service.dart';
import 'package:kilatex/core/models/transaction/transaction.dart';
import 'package:kilatex/core/models/transaction/transaction_type.enum.dart';
import 'package:kilatex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:kilatex/core/services/statement_import/models/extracted_row.dart';
import 'package:kilatex/core/services/statement_import/models/matching_result.dart';

class MatchingEngine {
  MatchingEngine({TransactionService? transactionService})
      : _transactionService = transactionService ?? TransactionService.instance;

  final TransactionService _transactionService;

  Future<List<MatchingResult>> matchRows({
    required String accountId,
    required List<ExtractedRow> rows,
    required DateTime? trackedSince,
  }) async {
    if (rows.isEmpty) return const [];

    final sortedDates = rows.map((r) => r.date).toList()
      ..sort((a, b) => a.compareTo(b));
    final minDate = sortedDates.first.subtract(const Duration(days: 1));
    final maxDate = sortedDates.last.add(const Duration(days: 1));

    final existing = await _transactionService
        .getTransactions(
          filters: TransactionFilterSet(
            accountsIDs: [accountId],
            minDate: minDate,
            maxDate: maxDate,
            includeReceivingAccountsInAccountFilters: false,
          ),
        )
        .first;

    existing.sort((a, b) => a.date.compareTo(b.date));

    final consumed = <String>{};
    final results = <MatchingResult>[];

    for (final row in rows) {
      MoneyTransaction? best;
      double bestScore = 0;

      for (final tx in existing) {
        if (consumed.contains(tx.id)) continue;

        double score = 0;

        if (tx.date.year == row.date.year &&
            tx.date.month == row.date.month &&
            tx.date.day == row.date.day) {
          score += 0.4;
        }

        if ((tx.value.abs() - row.amount).abs() < 0.005) {
          score += 0.4;
        }

        final isIncomeRow = row.kind == 'income';
        final isExpenseRow = row.kind == 'expense' || row.kind == 'fee';
        if ((isIncomeRow && tx.type == TransactionType.income) ||
            (isExpenseRow && tx.type == TransactionType.expense)) {
          score += 0.2;
        }

        if (score >= 0.8 && score > bestScore) {
          bestScore = score;
          best = tx;
        }
      }

      final isPreFresh = trackedSince != null && row.date.isBefore(trackedSince);

      if (best != null) {
        consumed.add(best.id);
        results.add(MatchingResult(
          row: row,
          existsInApp: true,
          isPreFresh: isPreFresh,
          matchedTransactionId: best.id,
        ));
      } else {
        results.add(MatchingResult(
          row: row,
          existsInApp: false,
          isPreFresh: isPreFresh,
        ));
      }
    }

    return results;
  }
}
