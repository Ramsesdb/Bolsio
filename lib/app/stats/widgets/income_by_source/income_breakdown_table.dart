import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bolsio/app/stats/widgets/income_by_source/source_dimension_toggle.dart';
import 'package:bolsio/app/stats/widgets/movements_distribution/tr_distribution_chart_item.dart';
import 'package:bolsio/core/database/services/category/category_service.dart';
import 'package:bolsio/core/database/services/tags/tags_service.dart';
import 'package:bolsio/core/database/services/transaction/transaction_service.dart';
import 'package:bolsio/core/extensions/color.extensions.dart';
import 'package:bolsio/core/models/category/category.dart';
import 'package:bolsio/core/models/supported-icon/icon_displayer.dart';
import 'package:bolsio/core/models/tags/tag.dart';
import 'package:bolsio/core/models/transaction/transaction.dart';
import 'package:bolsio/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';

/// Detailed breakdown table showing amount + percentage per source,
/// ordered by amount descending.
class IncomeBreakdownTable extends StatelessWidget {
  const IncomeBreakdownTable({
    super.key,
    required this.filters,
    required this.dimension,
  });

  final TransactionFilterSet filters;
  final BreakdownDimension dimension;

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

    items.sort((a, b) => b.value.compareTo(a.value));
    return items;
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

    items.sort((a, b) => b.value.compareTo(a.value));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MoneyTransaction>>(
      stream: TransactionService.instance.getTransactions(filters: filters),
      builder: (context, trSnapshot) {
        if (!trSnapshot.hasData) {
          return const LinearProgressIndicator();
        }

        if (trSnapshot.data!.isEmpty) {
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: const Text(
              'Sin datos en este periodo', // TODO: i18n
              textAlign: TextAlign.center,
            ),
          );
        }

        if (dimension == BreakdownDimension.tag) {
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

              if (items.isEmpty) {
                return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(24),
                  child: const Text(
                    'Sin tags asignados a ingresos', // TODO: i18n
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final total = items.map((e) => e.value).sum;

              return _BreakdownListView<Tag>(
                items: items,
                total: total,
                nameBuilder: (tag) => tag.name,
                leadingBuilder: (tag) => tag.displayIcon(size: 20),
                colorBuilder: (tag) => tag.colorData,
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

            final items = catSnapshot.data!;

            if (items.isEmpty) {
              return Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: const Text(
                  'Sin categorías asignadas a ingresos', // TODO: i18n
                  textAlign: TextAlign.center,
                ),
              );
            }

            final total = items.map((e) => e.value).sum;

            return _BreakdownListView<Category>(
              items: items,
              total: total,
              nameBuilder: (cat) => cat.name,
              leadingBuilder: (cat) => IconDisplayer.fromCategory(
                context,
                category: cat,
                size: 20,
              ),
              colorBuilder: (cat) => ColorHex.get(cat.color),
            );
          },
        );
      },
    );
  }
}

class _BreakdownListView<T> extends StatelessWidget {
  const _BreakdownListView({
    required this.items,
    required this.total,
    required this.nameBuilder,
    required this.leadingBuilder,
    required this.colorBuilder,
  });

  final List<TrDistributionChartItem<T>> items;
  final double total;
  final String Function(T) nameBuilder;
  final Widget Function(T) leadingBuilder;
  final Color Function(T) colorBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final item = items[index];
        final percentage = total > 0 ? item.value / total : 0.0;

        return ListTile(
          leading: leadingBuilder(item.category),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(nameBuilder(item.category))),
              CurrencyDisplayer(amountToConvert: item.value),
            ],
          ),
          subtitle: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${item.transactions.length} transacción${item.transactions.length != 1 ? "es" : ""}', // TODO: i18n
              ),
              Text(
                NumberFormat.decimalPercentPattern(decimalDigits: 1)
                    .format(percentage),
              ),
            ],
          ),
        );
      },
    );
  }
}
