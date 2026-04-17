import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:wallex/app/stats/widgets/income_by_source/source_dimension_toggle.dart';
import 'package:wallex/app/stats/widgets/movements_distribution/tr_distribution_chart_item.dart';
import 'package:wallex/core/database/services/category/category_service.dart';
import 'package:wallex/core/database/services/tags/tags_service.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/extensions/color.extensions.dart';
import 'package:wallex/core/models/category/category.dart';
import 'package:wallex/core/models/tags/tag.dart';
import 'package:wallex/core/models/transaction/transaction.dart';
import 'package:wallex/core/presentation/widgets/number_ui_formatters/ui_number_formatter.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

/// Pie chart showing total income breakdown by tag or category for the entire
/// date range (no temporal granularity). Follows the same pattern as
/// `pie_chart_by_categories.dart`.
class IncomePieChart extends StatefulWidget {
  const IncomePieChart({
    super.key,
    required this.filters,
    required this.dimension,
  });

  final TransactionFilterSet filters;
  final BreakdownDimension dimension;

  @override
  State<IncomePieChart> createState() => _IncomePieChartState();
}

class _IncomePieChartState extends State<IncomePieChart> {
  int touchedIndex = -1;
  static const double _centerRadius = 35;

  List<TrDistributionChartItem<Tag>> _buildTagItems(
    List<MoneyTransaction> transactions,
    List<Tag> tags,
  ) {
    final items = <TrDistributionChartItem<Tag>>[];

    for (final tag in tags) {
      final tagTxs = transactions
          .where((tx) => tx.tags.any((t) => t.id == tag.id))
          .toList();

      if (tagTxs.isNotEmpty) {
        items.add(TrDistributionChartItem<Tag>(
          category: tag,
          transactions: tagTxs,
          value: tagTxs.map((e) => e.currentValueInPreferredCurrency ?? 0.0).sum,
        ));
      }
    }

    return items.sorted((a, b) => b.value.compareTo(a.value));
  }

  Future<List<TrDistributionChartItem<Category>>> _buildCategoryItems(
    List<MoneyTransaction> transactions,
  ) async {
    final items = <TrDistributionChartItem<Category>>[];

    for (final tx in transactions) {
      final trValue = tx.currentValueInPreferredCurrency ?? 0.0;

      final existingItem = items.firstWhereOrNull(
        (item) =>
            item.category.id == tx.category?.id ||
            item.category.id == tx.category?.parentCategoryID,
      );

      if (existingItem != null) {
        existingItem.value += trValue;
        existingItem.transactions.add(tx);
      } else if (tx.category != null) {
        final cat = tx.category!.parentCategoryID == null
            ? Category.fromDB(tx.category!, null)
            : (await CategoryService.instance
                  .getCategoryById(tx.category!.parentCategoryID!)
                  .first) ??
              Category.fromDB(tx.category!, null);

        items.add(TrDistributionChartItem<Category>(
          category: cat,
          transactions: [tx],
          value: trValue,
        ));
      }
    }

    return items
        .where((e) => e.value > 0)
        .sorted((a, b) => b.value.compareTo(a.value));
  }

  double _getPercentage(double value, List<TrDistributionChartItem> items) {
    final total = items.map((e) => e.value).sum;
    return total > 0 ? value / total : 0;
  }

  List<PieChartSectionData> _buildSections<T>({
    required List<TrDistributionChartItem<T>> data,
    required Color Function(T) colorGetter,
  }) {
    if (data.isEmpty) {
      return [
        PieChartSectionData(
          color: Colors.grey.withValues(alpha: 0.175),
          value: 100,
          radius: 50,
          showTitle: false,
        ),
      ];
    }

    double totalPercentAccumulated = 0;

    return data.mapIndexed((index, element) {
      final isTouched = index == touchedIndex;
      final radius = isTouched ? 60.0 : 50.0;
      final percentage = _getPercentage(element.value, data);
      totalPercentAccumulated += percentage;

      final showBadge = percentage > 0.05;

      return PieChartSectionData(
        color: colorGetter(element.category),
        value: percentage,
        title: '',
        radius: radius,
        titlePositionPercentageOffset: 1.4,
        badgePositionPercentageOffset: .98,
        badgeWidget: !showBadge
            ? null
            : Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isTouched ? 1 : 0,
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          totalPercentAccumulated - percentage / 2 < 0.5
                              ? -34
                              : 34,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: colorGetter(element.category),
                              width: 1.5,
                            ),
                            color: Theme.of(context).canvasColor,
                          ),
                          child: UINumberFormatter.percentage(
                            amountToConvert: percentage,
                            showDecimals: false,
                            integerStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ).getTextWidget(context),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).canvasColor,
                      border: Border.all(
                        width: 2,
                        color: colorGetter(element.category),
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.circle,
                      size: 12,
                      color: colorGetter(element.category),
                    ),
                  ),
                ],
              ),
      );
    }).toList();
  }

  Widget _buildPieChart<T>({
    required List<TrDistributionChartItem<T>> data,
    required Color Function(T) colorGetter,
  }) {
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          RepaintBoundary(
            child: PieChart(
              curve: Curves.easeOut,
              duration: const Duration(milliseconds: 250),
              PieChartData(
                startDegreeOffset: -45,
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        touchedIndex = -1;
                        return;
                      }
                      touchedIndex =
                          pieTouchResponse.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 0,
                centerSpaceRadius: _centerRadius,
                sections: _buildSections(
                  data: data,
                  colorGetter: colorGetter,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(
                width: _centerRadius * 2.25,
                height: _centerRadius * 2.25,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
                ),
              ),
            ),
          ),
          if (data.isEmpty)
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  'Sin datos en este periodo', // TODO: i18n
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MoneyTransaction>>(
      stream: TransactionService.instance.getTransactions(filters: widget.filters),
      builder: (context, trSnapshot) {
        if (!trSnapshot.hasData) {
          return const LinearProgressIndicator();
        }

        if (trSnapshot.data!.isEmpty) {
          return _buildPieChart<Tag>(data: [], colorGetter: (t) => t.colorData);
        }

        if (widget.dimension == BreakdownDimension.tag) {
          return StreamBuilder<List<Tag>>(
            stream: TagService.instance.getTags(),
            builder: (context, tagsSnapshot) {
              if (!tagsSnapshot.hasData) {
                return const LinearProgressIndicator();
              }

              final items = _buildTagItems(
                trSnapshot.data!,
                tagsSnapshot.data!,
              );

              return _buildPieChart<Tag>(
                data: items,
                colorGetter: (tag) => tag.colorData,
              );
            },
          );
        }

        // Category dimension
        return FutureBuilder<List<TrDistributionChartItem<Category>>>(
          future: _buildCategoryItems(trSnapshot.data!),
          builder: (context, catSnapshot) {
            if (!catSnapshot.hasData) {
              return const LinearProgressIndicator();
            }

            return _buildPieChart<Category>(
              data: catSnapshot.data!,
              colorGetter: (cat) => ColorHex.get(cat.color),
            );
          },
        );
      },
    );
  }
}
