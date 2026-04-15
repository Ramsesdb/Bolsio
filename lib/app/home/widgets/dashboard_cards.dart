import 'package:flutter/material.dart';
import 'package:wallex/app/stats/stats_page.dart';
import 'package:wallex/app/stats/widgets/balance_bar_chart.dart';
import 'package:wallex/app/stats/widgets/finance_health/finance_health_main_info.dart';
import 'package:wallex/app/stats/widgets/fund_evolution_info.dart';
import 'package:wallex/app/stats/widgets/movements_distribution/pie_chart_by_categories.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/core/presentation/responsive/breakpoints.dart';
import 'package:wallex/core/presentation/responsive/responsive_row_column.dart';
import 'package:wallex/core/presentation/widgets/card_with_header.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/finance_health_service.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class DashboardCards extends StatelessWidget {
  const DashboardCards({super.key, required this.dateRangeService});

  final DatePeriodState dateRangeService;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return ResponsiveRowColumn.withSymetricSpacing(
      direction: BreakPoint.of(context).isLargerThan(BreakpointID.md)
          ? Axis.horizontal
          : Axis.vertical,
      rowCrossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        ResponsiveRowColumnItem(
          rowFit: FlexFit.tight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CardWithHeader(
                title: t.financial_health.display,
                footer: CardFooterWithSingleButton(
                  onButtonClick: () => RouteUtils.pushRoute(
                    StatsPage(
                      dateRangeService: dateRangeService,
                      initialIndex: 0,
                    ),
                  ),
                ),
                bodyPadding: const EdgeInsets.all(16),
                body: StreamBuilder(
                  stream: FinanceHealthService().getHealthyValue(
                    filters: TransactionFilterSet(
                      minDate: dateRangeService.startDate,
                      maxDate: dateRangeService.endDate,
                    ),
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }

                    final financeHealthData = snapshot.data!;

                    return FinanceHealthMainInfo(
                      financeHealthData: financeHealthData,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              CardWithHeader(
                title: t.stats.by_categories,
                body: PieChartByCategories(datePeriodState: dateRangeService),
                footer: CardFooterWithSingleButton(
                  onButtonClick: () => RouteUtils.pushRoute(
                    StatsPage(
                      dateRangeService: dateRangeService,
                      initialIndex: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ResponsiveRowColumnItem(
          rowFit: FlexFit.tight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CardWithHeader(
                title: t.stats.balance_evolution,
                bodyPadding: const EdgeInsets.all(16),
                body: FundEvolutionInfo(dateRange: dateRangeService),
                footer: CardFooterWithSingleButton(
                  onButtonClick: () {
                    RouteUtils.pushRoute(
                      StatsPage(
                        dateRangeService: dateRangeService,
                        initialIndex: 2,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              CardWithHeader(
                title: t.stats.by_periods,
                bodyPadding: const EdgeInsets.only(
                  bottom: 12,
                  top: 24,
                  right: 16,
                ),
                body: BalanceBarChart(
                  dateRange: dateRangeService,
                  filters: TransactionFilterSet(
                    minDate: dateRangeService.startDate,
                    maxDate: dateRangeService.endDate,
                  ),
                ),
                footer: CardFooterWithSingleButton(
                  onButtonClick: () {
                    RouteUtils.pushRoute(
                      StatsPage(
                        dateRangeService: dateRangeService,
                        initialIndex: 3,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
