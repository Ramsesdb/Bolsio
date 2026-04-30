import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bolsio/app/stats/utils/common_axis_titles.dart';
import 'package:bolsio/app/stats/widgets/income_by_source/source_dimension_toggle.dart';
import 'package:bolsio/core/database/services/category/category_service.dart';
import 'package:bolsio/core/database/services/currency/currency_service.dart';
import 'package:bolsio/core/database/services/tags/tags_service.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/extensions/color.extensions.dart';
import 'package:bolsio/core/models/date-utils/date_period_state.dart';
import 'package:bolsio/core/models/date-utils/period_type.dart';
import 'package:bolsio/core/models/date-utils/periodicity.dart';
import 'package:bolsio/core/models/tags/tag.dart';
import 'package:bolsio/core/models/transaction/transaction.dart';
import 'package:bolsio/core/presentation/theme.dart';
import 'package:bolsio/core/presentation/widgets/number_ui_formatters/ui_number_formatter.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

/// A bucket of transactions grouped by a time period for the stacked bar chart.
class _TimeBucket {
  final DateTime start;
  final DateTime end;
  final String shortTitle;
  final String longTitle;
  final List<MoneyTransaction> transactions;

  _TimeBucket({
    required this.start,
    required this.end,
    required this.shortTitle,
    required this.longTitle,
    required this.transactions,
  });
}

/// A source slice within a stacked bar (a tag or category contribution).
class _SourceSlice {
  final String name;
  final Color color;
  final double amount;

  _SourceSlice({
    required this.name,
    required this.color,
    required this.amount,
  });
}

/// Stacked bar chart that shows income evolution by time period,
/// with segments colored by tag or category.
class IncomeStackedBarChart extends StatefulWidget {
  const IncomeStackedBarChart({
    super.key,
    required this.filters,
    required this.dimension,
    required this.dateRange,
  });

  final TransactionFilterSet filters;
  final BreakdownDimension dimension;
  final DatePeriodState dateRange;

  @override
  State<IncomeStackedBarChart> createState() => _IncomeStackedBarChartState();
}

class _IncomeStackedBarChartState extends State<IncomeStackedBarChart> {
  int touchedBarGroupIndex = -1;

  /// Determine time buckets based on the date period configuration.
  /// Follows the same bucketing logic as `BalanceBarChart`.
  List<_TimeBucket> _buildTimeBuckets(List<MoneyTransaction> allTransactions) {
    final startDate = widget.dateRange.startDate;
    final endDate = widget.dateRange.endDate;
    final buckets = <_TimeBucket>[];

    if (startDate == null || endDate == null) {
      // All time: bucket by year
      if (allTransactions.isEmpty) return buckets;

      final years = allTransactions.map((t) => t.date.year).toSet().toList()
        ..sort();
      if (years.isEmpty) return buckets;

      for (final year in years) {
        final start = DateTime(year);
        final end = DateTime(year + 1);
        buckets.add(_TimeBucket(
          start: start,
          end: end,
          shortTitle: DateFormat.y().format(start),
          longTitle: DateFormat.y().format(start),
          transactions: allTransactions
              .where((t) =>
                  !t.date.isBefore(start) && t.date.isBefore(end))
              .toList(),
        ));
      }
      return buckets;
    }

    final periodType = widget.dateRange.datePeriod.periodType;
    final periodicity = widget.dateRange.datePeriod.periodicity;

    if (periodType == PeriodType.cycle) {
      switch (periodicity) {
        case Periodicity.day:
          // Single day: just one aggregated bar
          buckets.add(_TimeBucket(
            start: startDate,
            end: endDate,
            shortTitle: DateFormat.MMMd().format(startDate),
            longTitle: DateFormat.yMMMEd().format(startDate),
            transactions: allTransactions,
          ));
          break;

        case Periodicity.week:
          for (var i = 0; i < DateTime.daysPerWeek; i++) {
            final start = startDate.add(Duration(days: i));
            final end = start.add(const Duration(days: 1));
            buckets.add(_TimeBucket(
              start: start,
              end: end,
              shortTitle: DateFormat.E().format(start),
              longTitle: DateFormat.yMMMEd().format(start),
              transactions: allTransactions
                  .where((t) =>
                      !t.date.isBefore(start) && t.date.isBefore(end))
                  .toList(),
            ));
          }
          break;

        case Periodicity.month:
          // Split month into ~5 ranges (same as BalanceBarChart)
          final ranges = [
            [1, 6],
            [6, 10],
            [10, 15],
            [15, 20],
            [20, 25],
            [25, null],
          ];
          for (final r in ranges) {
            final start =
                DateTime(startDate.year, startDate.month, r[0]!);
            final end = DateTime(
              start.year,
              r[1] == null ? start.month + 1 : start.month,
              r[1] ?? 1,
            );
            buckets.add(_TimeBucket(
              start: start,
              end: end,
              shortTitle: '${r[0]}-${r[1] ?? ''}',
              longTitle:
                  '${DateFormat.MMMd().format(start)} - ${DateFormat.MMMd().format(end)}',
              transactions: allTransactions
                  .where((t) =>
                      !t.date.isBefore(start) && t.date.isBefore(end))
                  .toList(),
            ));
          }
          break;

        case Periodicity.year:
          for (
            var i = startDate.month;
            i <= endDate.subtract(const Duration(milliseconds: 1)).month;
            i++
          ) {
            final start = DateTime(startDate.year, i);
            final end = DateTime(start.year, i + 1);
            buckets.add(_TimeBucket(
              start: start,
              end: end,
              shortTitle: DateFormat.MMM().format(start),
              longTitle: DateFormat.MMMM().format(start),
              transactions: allTransactions
                  .where((t) =>
                      !t.date.isBefore(start) && t.date.isBefore(end))
                  .toList(),
            ));
          }
          break;
      }
    } else {
      // dateRange, lastDays, allTime: infer periodicity from day span
      final dayDiff = endDate.difference(startDate).inDays;

      if (dayDiff <= 7) {
        // Day-level buckets
        for (var i = 0; i < dayDiff; i++) {
          final start = startDate.add(Duration(days: i));
          final end = start.add(const Duration(days: 1));
          buckets.add(_TimeBucket(
            start: start,
            end: end,
            shortTitle: DateFormat.E().format(start),
            longTitle: DateFormat.yMMMEd().format(start),
            transactions: allTransactions
                .where((t) =>
                    !t.date.isBefore(start) && t.date.isBefore(end))
                .toList(),
          ));
        }
      } else if (dayDiff <= 31) {
        // Week-level buckets within the month
        final ranges = [
          [1, 6],
          [6, 10],
          [10, 15],
          [15, 20],
          [20, 25],
          [25, null],
        ];
        for (final r in ranges) {
          final start =
              DateTime(startDate.year, startDate.month, r[0]!);
          final end = DateTime(
            start.year,
            r[1] == null ? start.month + 1 : start.month,
            r[1] ?? 1,
          );
          if (end.isAfter(endDate.add(const Duration(days: 1)))) continue;
          buckets.add(_TimeBucket(
            start: start,
            end: end,
            shortTitle: '${r[0]}-${r[1] ?? ''}',
            longTitle:
                '${DateFormat.MMMd().format(start)} - ${DateFormat.MMMd().format(end)}',
            transactions: allTransactions
                .where((t) =>
                    !t.date.isBefore(start) && t.date.isBefore(end))
                .toList(),
          ));
        }
      } else if (dayDiff <= 365) {
        // Month-level buckets
        var current = DateTime(startDate.year, startDate.month);
        while (current.isBefore(endDate)) {
          final start = current;
          final end = DateTime(current.year, current.month + 1);
          buckets.add(_TimeBucket(
            start: start,
            end: end,
            shortTitle: DateFormat.MMM().format(start),
            longTitle: DateFormat.MMMM().format(start),
            transactions: allTransactions
                .where((t) =>
                    !t.date.isBefore(start) && t.date.isBefore(end))
                .toList(),
          ));
          current = end;
        }
      } else {
        // Year-level buckets
        for (var year = startDate.year; year <= endDate.year; year++) {
          final start = DateTime(year);
          final end = DateTime(year + 1);
          buckets.add(_TimeBucket(
            start: start,
            end: end,
            shortTitle: DateFormat.y().format(start),
            longTitle: DateFormat.y().format(start),
            transactions: allTransactions
                .where((t) =>
                    !t.date.isBefore(start) && t.date.isBefore(end))
                .toList(),
          ));
        }
      }
    }

    return buckets;
  }

  /// Build stacked slices for a single bucket by tag.
  List<_SourceSlice> _slicesByTag(
    List<MoneyTransaction> transactions,
    List<Tag> tags,
  ) {
    final slices = <_SourceSlice>[];

    for (final tag in tags) {
      final tagTxs =
          transactions.where((tx) => tx.tags.any((t) => t.id == tag.id));
      final amount =
          tagTxs.map((e) => e.currentValueInPreferredCurrency ?? 0.0).sum;

      if (amount > 0) {
        slices.add(_SourceSlice(
          name: tag.name,
          color: tag.colorData,
          amount: amount,
        ));
      }
    }

    // Also handle transactions with no tags
    final noTagTxs =
        transactions.where((tx) => tx.tags.isEmpty);
    final noTagAmount =
        noTagTxs.map((e) => e.currentValueInPreferredCurrency ?? 0.0).sum;
    if (noTagAmount > 0) {
      slices.add(_SourceSlice(
        name: 'Sin tag', // TODO: i18n
        color: Colors.grey,
        amount: noTagAmount,
      ));
    }

    return slices;
  }

  /// Build stacked slices for a single bucket by category.
  Future<List<_SourceSlice>> _slicesByCategory(
    List<MoneyTransaction> transactions,
  ) async {
    final catMap = <String, _SourceSlice>{};

    for (final tx in transactions) {
      final trValue = tx.currentValueInPreferredCurrency ?? 0.0;
      if (trValue <= 0) continue;

      String catId;
      String catName;
      Color catColor;

      if (tx.category != null) {
        final parentId = tx.category!.parentCategoryID;
        if (parentId != null) {
          final parent = await CategoryService.instance
              .getCategoryById(parentId)
              .first;
          catId = parent?.id ?? tx.category!.id;
          catName = parent?.name ?? tx.category!.name;
          catColor = ColorHex.get(parent?.color ?? tx.category!.color);
        } else {
          catId = tx.category!.id;
          catName = tx.category!.name;
          catColor = ColorHex.get(tx.category!.color);
        }
      } else {
        catId = '_unknown';
        catName = 'Sin categoría'; // TODO: i18n
        catColor = Colors.grey;
      }

      if (catMap.containsKey(catId)) {
        catMap[catId] = _SourceSlice(
          name: catMap[catId]!.name,
          color: catMap[catId]!.color,
          amount: catMap[catId]!.amount + trValue,
        );
      } else {
        catMap[catId] = _SourceSlice(
          name: catName,
          color: catColor,
          amount: trValue,
        );
      }
    }

    return catMap.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: StreamBuilder(
        stream: CurrencyService.instance.ensureAndGetPreferredCurrency(),
        builder: (context, currSnapshot) {
          return StreamBuilder<List<MoneyTransaction>>(
            stream: TransactionService.instance
                .getTransactions(filters: widget.filters),
            builder: (context, trSnapshot) {
              if (!trSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (trSnapshot.data!.isEmpty) {
                return Center(
                  child: Text(
                    'Sin datos en este periodo', // TODO: i18n
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                );
              }

              final buckets = _buildTimeBuckets(trSnapshot.data!);

              if (widget.dimension == BreakdownDimension.tag) {
                return StreamBuilder<List<Tag>>(
                  stream: TagService.instance.getTags(),
                  builder: (context, tagsSnapshot) {
                    if (!tagsSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final barGroups = <BarChartGroupData>[];
                    final shortTitles = <String>[];
                    final longTitles = <String>[];

                    for (var i = 0; i < buckets.length; i++) {
                      final bucket = buckets[i];
                      shortTitles.add(bucket.shortTitle);
                      longTitles.add(bucket.longTitle);

                      final slices =
                          _slicesByTag(bucket.transactions, tagsSnapshot.data!);

                      barGroups.add(
                        _buildBarGroup(i, slices, buckets.length),
                      );
                    }

                    return _buildChart(
                      barGroups: barGroups,
                      shortTitles: shortTitles,
                      longTitles: longTitles,
                      currency: currSnapshot.data,
                    );
                  },
                );
              }

              // Category dimension — needs async resolution
              return FutureBuilder<List<BarChartGroupData>>(
                future: _buildCategoryBarGroups(buckets),
                builder: (context, barSnapshot) {
                  if (!barSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return _buildChart(
                    barGroups: barSnapshot.data!,
                    shortTitles: buckets.map((b) => b.shortTitle).toList(),
                    longTitles: buckets.map((b) => b.longTitle).toList(),
                    currency: currSnapshot.data,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<BarChartGroupData>> _buildCategoryBarGroups(
    List<_TimeBucket> buckets,
  ) async {
    final barGroups = <BarChartGroupData>[];

    for (var i = 0; i < buckets.length; i++) {
      final slices = await _slicesByCategory(buckets[i].transactions);
      barGroups.add(_buildBarGroup(i, slices, buckets.length));
    }

    return barGroups;
  }

  BarChartGroupData _buildBarGroup(
    int x,
    List<_SourceSlice> slices,
    int totalBuckets,
  ) {
    final isTouched = touchedBarGroupIndex == x;
    final barWidth = (150 / totalBuckets).clamp(8.0, 28.0);

    if (slices.isEmpty) {
      return BarChartGroupData(
        x: x,
        barRods: [
          BarChartRodData(
            toY: 0,
            color: Colors.grey.withValues(alpha: 0.3),
            width: barWidth,
          ),
        ],
      );
    }

    final stackItems = <BarChartRodStackItem>[];
    double cumulative = 0;

    for (final slice in slices) {
      stackItems.add(BarChartRodStackItem(
        cumulative,
        cumulative + slice.amount,
        isTouched ? slice.color.lighten(0.2) : slice.color,
      ));
      cumulative += slice.amount;
    }

    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: cumulative,
          rodStackItems: stackItems,
          width: barWidth * (isTouched ? 1.15 : 1),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(barWidth / 6),
            topRight: Radius.circular(barWidth / 6),
          ),
          color: Colors.transparent,
        ),
      ],
    );
  }

  Widget _buildChart({
    required List<BarChartGroupData> barGroups,
    required List<String> shortTitles,
    required List<String> longTitles,
    dynamic currency,
  }) {
    final ultraLightBorderColor = isAppInLightBrightness(context)
        ? Colors.black12
        : Colors.white12;

    final allZero = barGroups.every(
      (g) => g.barRods.every((r) => r.toY == 0),
    );

    return BarChart(
      BarChartData(
        maxY: allZero ? 10.2 : null,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideVertically: true,
            fitInsideHorizontally: true,
            getTooltipColor: (spot) =>
                Theme.of(context).colorScheme.surface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final title = groupIndex < longTitles.length
                  ? longTitles[groupIndex]
                  : '';

              final children = <TextSpan>[];
              for (final stackItem in rod.rodStackItems) {
                final amount = stackItem.toY - stackItem.fromY;
                if (amount <= 0) continue;
                children.add(const TextSpan(text: '\n'));
                children.add(TextSpan(
                  text: '● ',
                  style: TextStyle(
                    color: stackItem.color,
                    fontSize: 12,
                    decoration: TextDecoration.none,
                  ),
                ));
                children.addAll(
                  UINumberFormatter.currency(
                    currency: currency,
                    amountToConvert: amount,
                  ).getTextSpanList(context),
                );
              }

              return BarTooltipItem(
                title,
                const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
                textAlign: TextAlign.start,
                children: children,
              );
            },
          ),
          touchCallback: (event, barTouchResponse) {
            if (!event.isInterestedForInteractions ||
                barTouchResponse == null ||
                barTouchResponse.spot == null) {
              touchedBarGroupIndex = -1;
              return;
            }
            touchedBarGroupIndex =
                barTouchResponse.spot!.touchedBarGroupIndex;
            setState(() {});
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= shortTitles.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    shortTitles[idx],
                    style: smallAxisTitleStyle(context),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value == meta.max) {
                  return Container();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    meta.formattedValue,
                    style: smallAxisTitleStyle(context),
                  ),
                );
              },
              reservedSize: 42,
            ),
          ),
          rightTitles: noAxisTitles,
          topTitles: noAxisTitles,
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              width: 1,
              color: ultraLightBorderColor,
            ),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return defaultGridLine(value).copyWith(
              strokeWidth: 0.5,
              color: ultraLightBorderColor,
            );
          },
        ),
        barGroups: barGroups,
      ),
    );
  }
}
