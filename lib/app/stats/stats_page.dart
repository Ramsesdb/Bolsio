import 'package:flutter/material.dart';
import 'package:nitido/app/layout/page_framework.dart';
import 'package:nitido/app/stats/widgets/balance_bar_chart.dart';
import 'package:nitido/app/stats/widgets/finance_health_details.dart';
import 'package:nitido/app/stats/widgets/fund_evolution_info.dart';
import 'package:nitido/app/stats/widgets/income_expense_comparason.dart';
import 'package:nitido/app/stats/widgets/income_by_source/income_by_source_tab.dart';
import 'package:nitido/app/stats/widgets/movements_distribution/pie_chart_by_categories.dart';
import 'package:nitido/app/stats/widgets/movements_distribution/tags_stats.dart';
import 'package:nitido/core/database/services/account/account_service.dart';
import 'package:nitido/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:nitido/core/models/date-utils/date_period_state.dart';
import 'package:nitido/core/presentation/responsive/breakpoints.dart';
import 'package:nitido/core/presentation/widgets/card_with_header.dart';
import 'package:nitido/core/presentation/widgets/dates/segmented_calendar_button.dart';
import 'package:nitido/core/presentation/widgets/filter_row_indicator.dart';
import 'package:nitido/core/presentation/widgets/persistent_footer_button.dart';
import 'package:nitido/core/presentation/widgets/transaction_filter/transaction_filter_sheet_modal.dart';
import 'package:nitido/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

import '../../core/models/transaction/transaction_type.enum.dart';
import '../accounts/all_accounts_balance.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    this.initialIndex = 0,
    this.filters = const TransactionFilterSet(),
    this.dateRangeService = const DatePeriodState(),
  });

  final int initialIndex;

  final TransactionFilterSet filters;
  final DatePeriodState dateRangeService;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage>
    with SingleTickerProviderStateMixin {
  final accountService = AccountService.instance;

  late TransactionFilterSet filters;
  late DatePeriodState dateRangeService;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    filters = widget.filters;
    dateRangeService = widget.dateRangeService;

    _tabController = TabController(
      length: 5,
      initialIndex: widget.initialIndex,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Intersects the user-selected [base.accountsIDs] with the Hidden Mode
  /// [visibleIds] stream snapshot. When the stream hasn't emitted yet
  /// ([visibleIds] is null) we fall back to [base] so the first frame isn't
  /// blank while subscription completes. When the user hadn't set an account
  /// filter we just forward the visible ids.
  TransactionFilterSet _applyVisibleAccountsFilter(
    TransactionFilterSet base,
    List<String>? visibleIds,
  ) {
    if (visibleIds == null) return base;

    final baseIds = base.accountsIDs;
    final Iterable<String> merged = baseIds == null
        ? visibleIds
        : baseIds.where(visibleIds.toSet().contains).toList(growable: false);

    return base.copyWith(accountsIDs: merged);
  }

  Widget buildContainerWithPadding(
    List<Widget> children, {
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      vertical: 16,
      horizontal: 16,
    ),
  }) {
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PageFramework(
      title: t.stats.title,
      appBarActions: [
        if (BreakPoint.of(context).isLargerOrEqualTo(BreakpointID.md)) ...[
          SizedBox(
            width: 300,
            child: SegmentedCalendarButton(
              initialDatePeriodService: dateRangeService,
              borderRadius: 499,
              buttonHeight: 32,
              onChanged: (value) {
                setState(() {
                  dateRangeService = value;
                });
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
        IconButton(
          onPressed: () async {
            final modalRes = await openFilterSheetModal(
              context,
              FilterSheetModal(
                preselectedFilter: filters,
                showDateFilter: false,
              ),
            );

            if (modalRes != null) {
              setState(() {
                filters = modalRes;
              });
            }
          },
          icon: const Icon(Icons.filter_alt_outlined),
        ),
      ],
      tabBar: TabBar(
        tabAlignment: BreakPoint.of(context).isSmallerThan(BreakpointID.md)
            ? TabAlignment.center
            : TabAlignment.start,
        isScrollable: true,
        controller: _tabController,
        tabs: [
          Tab(text: t.financial_health.display),
          const Tab(text: 'Ingresos', icon: Icon(Icons.trending_up, size: 18)), // TODO: i18n
          Tab(text: t.stats.distribution),
          Tab(text: t.stats.balance),
          Tab(text: t.stats.cash_flow),
        ],
      ),
      persistentFooterButtons:
          BreakPoint.of(context).isLargerOrEqualTo(BreakpointID.md)
          ? null
          : [
              PersistentFooterButton(
                child: SegmentedCalendarButton(
                  initialDatePeriodService: dateRangeService,
                  borderRadius: 8,
                  buttonHeight: 44,
                  border: Border.all(
                    width: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onChanged: (value) {
                    setState(() {
                      dateRangeService = value;
                    });
                  },
                ),
              ),
            ],

      body: Column(
        children: [
          if (filters.hasFilter) ...[
            FilterRowIndicator(
              filters: filters,
              onChange: (newFilters) {
                setState(() {
                  filters = newFilters;
                });
              },
            ),
            const Divider(),
          ],
          Expanded(
            // Single visibility subscription for every tab. While Hidden Mode
            // is locked the stream emits the non-savings account ids, which
            // we intersect with any explicit account filter the user already
            // set. When the feature is disabled the stream emits every id so
            // the intersection is a no-op.
            child: StreamBuilder<List<String>>(
              stream: HiddenModeService.instance.visibleAccountIdsStream,
              builder: (context, snapshot) {
                final visibleIds = snapshot.data;
                final effectiveFilters = _applyVisibleAccountsFilter(
                  filters,
                  visibleIds,
                );

                return TabBarView(
                  controller: _tabController,
                  children: [
                    buildContainerWithPadding([
                      FinanceHealthDetails(
                        filters: effectiveFilters.copyWith(
                          minDate: dateRangeService.startDate,
                          maxDate: dateRangeService.endDate,
                        ),
                      ),
                    ]),
                    IncomeBySourceTab(
                      filters: effectiveFilters,
                      dateRangeService: dateRangeService,
                    ),
                    buildContainerWithPadding([
                      CardWithHeader(
                        title: t.stats.by_categories,
                        body: PieChartByCategories(
                          datePeriodState: dateRangeService,
                          showList: true,
                          initialSelectedType: TransactionType.expense,
                          filters: effectiveFilters,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CardWithHeader(
                        title: t.stats.by_tags,
                        body: TagStats(
                          filters: effectiveFilters.copyWith(
                            minDate: dateRangeService.startDate,
                            maxDate: dateRangeService.endDate,
                          ),
                        ),
                      ),
                    ]),
                    buildContainerWithPadding([
                      CardWithHeader(
                        title: t.stats.balance_evolution,
                        subtitle: t.stats.balance_evolution_subtitle,
                        bodyPadding: const EdgeInsets.only(
                          bottom: 12,
                          top: 16,
                          right: 16,
                          left: 16,
                        ),
                        body: FundEvolutionInfo(
                          showBalanceHeader: true,
                          dateRange: dateRangeService,
                          filters: effectiveFilters,
                        ),
                      ),
                      const SizedBox(height: 16),
                      AllAccountBalancePage(
                        date: dateRangeService.endDate ?? DateTime.now(),
                        filters: effectiveFilters,
                      ),
                    ]),
                    buildContainerWithPadding([
                      CardWithHeader(
                        title: t.stats.cash_flow,
                        subtitle: t.stats.cash_flow_subtitle,
                        body: IncomeExpenseComparason(
                          startDate: dateRangeService.startDate,
                          endDate: dateRangeService.endDate,
                          filters: effectiveFilters,
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
                          filters: effectiveFilters,
                        ),
                      ),
                    ]),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
