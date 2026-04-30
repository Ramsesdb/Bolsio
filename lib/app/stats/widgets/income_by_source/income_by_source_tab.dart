import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:bolsio/app/stats/widgets/income_by_source/income_breakdown_table.dart';
import 'package:bolsio/app/stats/widgets/income_by_source/income_pie_chart.dart';
import 'package:bolsio/app/stats/widgets/income_by_source/income_stacked_bar_chart.dart';
import 'package:bolsio/app/stats/widgets/income_by_source/source_dimension_toggle.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/models/date-utils/date_period_state.dart';
import 'package:bolsio/core/models/transaction/transaction.dart';
import 'package:bolsio/core/models/transaction/transaction_type.enum.dart';
import 'package:bolsio/core/presentation/widgets/card_with_header.dart';
import 'package:bolsio/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

/// Main widget for the "Ingresos" (Income) tab in StatsPage.
/// Shows a scrollable composition of KPI, stacked bar chart, pie chart,
/// and detailed breakdown table, with a toggle for tag vs category dimension.
class IncomeBySourceTab extends StatefulWidget {
  const IncomeBySourceTab({
    super.key,
    required this.filters,
    required this.dateRangeService,
  });

  final TransactionFilterSet filters;
  final DatePeriodState dateRangeService;

  @override
  State<IncomeBySourceTab> createState() => _IncomeBySourceTabState();
}

class _IncomeBySourceTabState extends State<IncomeBySourceTab> {
  BreakdownDimension _dimension = BreakdownDimension.tag;

  TransactionFilterSet get _incomeFilters => widget.filters.copyWith(
        transactionTypes: [TransactionType.income],
        minDate: widget.dateRangeService.startDate,
        maxDate: widget.dateRangeService.endDate,
      );

  @override
  Widget build(BuildContext context) {
    final incomeFilters = _incomeFilters;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle Tag / Categoría
          Center(
            child: SourceDimensionToggle(
              value: _dimension,
              onChanged: (d) => setState(() => _dimension = d),
            ),
          ),
          const SizedBox(height: 16),

          // Total ingresos del periodo (KPI)
          CardWithHeader(
            title: 'Total ingresos del periodo', // TODO: i18n
            body: _TotalIncomeKPI(filters: incomeFilters),
          ),
          const SizedBox(height: 16),

          // Stacked bar chart — evolution by period
          CardWithHeader(
            title: 'Evolución por periodo', // TODO: i18n
            bodyPadding: const EdgeInsets.only(
              bottom: 12,
              top: 16,
              right: 16,
            ),
            body: IncomeStackedBarChart(
              filters: incomeFilters,
              dimension: _dimension,
              dateRange: widget.dateRangeService,
            ),
          ),
          const SizedBox(height: 16),

          // Pie chart — total breakdown
          CardWithHeader(
            title: _dimension == BreakdownDimension.tag
                ? 'Distribución por Tag' // TODO: i18n
                : 'Distribución por Categoría', // TODO: i18n
            body: IncomePieChart(
              filters: incomeFilters,
              dimension: _dimension,
            ),
          ),
          const SizedBox(height: 16),

          // Detailed breakdown table
          CardWithHeader(
            title: 'Desglose detallado', // TODO: i18n
            body: IncomeBreakdownTable(
              filters: incomeFilters,
              dimension: _dimension,
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays the total income amount for the filtered period as a prominent KPI.
class _TotalIncomeKPI extends StatelessWidget {
  const _TotalIncomeKPI({required this.filters});

  final TransactionFilterSet filters;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MoneyTransaction>>(
      stream: TransactionService.instance.getTransactions(filters: filters),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          );
        }

        final total = snapshot.data!
            .map((tx) => tx.currentValueInPreferredCurrency ?? 0.0)
            .sum;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Center(
            child: CurrencyDisplayer(
              amountToConvert: total,
              integerStyle: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
        );
      },
    );
  }
}
