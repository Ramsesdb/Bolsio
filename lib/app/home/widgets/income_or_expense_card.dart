import 'package:flutter/material.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../core/models/transaction/transaction_type.enum.dart';
import '../../../core/presentation/app_colors.dart';

class IncomeOrExpenseCard extends StatelessWidget {
  const IncomeOrExpenseCard({
    super.key,
    required this.type,
    required this.periodState,
    required this.labelStyle,
    this.filters,
    this.rateSource,
  });

  final TransactionType type;

  final DatePeriodState periodState;

  final TransactionFilterSet? filters;

  final TextStyle? labelStyle;

  /// Exchange rate source ('bcv' or 'paralelo'). When provided, a Bs
  /// equivalent line is shown below the dollar amount.
  final String? rateSource;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: type.color(context),
              borderRadius: BorderRadius.circular(80),
            ),
            child: Icon(
              type.icon,
              color: Theme.of(context).colorScheme.surface,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type.displayName(context), style: labelStyle),
              StreamBuilder<double>(
                stream: TransactionService.instance.getTransactionsValueBalance(
                  filters: TransactionFilterSet(
                    accountsIDs: filters?.accountsIDs,
                    categoriesIds: filters?.categoriesIds,
                    minDate: periodState.startDate,
                    maxDate: periodState.endDate,
                    transactionTypes: [type],
                  ),
                ),
                builder: (context, snapshot) {
                  final dollarAmount = snapshot.data?.abs() ?? 9999;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeletonizer(
                        enabled: !snapshot.hasData,
                        child: CurrencyDisplayer(
                          amountToConvert: dollarAmount,
                          compactView: true,
                          showDecimals: false,
                          integerStyle: TextStyle(
                            fontSize: 18,
                            color: AppColors.of(context).onConsistentPrimary,
                          ),
                        ),
                      ),
                      if (rateSource != null && snapshot.hasData)
                        StreamBuilder<double?>(
                          stream: ExchangeRateService.instance
                              .calculateExchangeRate(
                            fromCurrency: 'USD',
                            toCurrency: 'VES',
                            amount: dollarAmount,
                            source: rateSource,
                          ),
                          builder: (context, rateSnap) {
                            if (!rateSnap.hasData || rateSnap.data == null) {
                              return const SizedBox.shrink();
                            }
                            final vesAmount = rateSnap.data!;
                            final formatted = vesAmount
                                .toStringAsFixed(2)
                                .replaceAllMapped(
                                  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                                  (m) => '${m[1]}.',
                                );
                            return BlurBasedOnPrivateMode(
                              child: Text(
                                '≈ $formatted Bs',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.of(context)
                                      .onConsistentPrimary
                                      .withOpacity(0.7),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
