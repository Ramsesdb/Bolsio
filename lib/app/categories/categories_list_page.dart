import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:nitido/app/categories/form/category_form.dart';
import 'package:nitido/app/layout/page_framework.dart';
import 'package:nitido/core/database/services/category/category_service.dart';
import 'package:nitido/core/extensions/string.extension.dart';
import 'package:nitido/core/models/supported-icon/icon_displayer.dart';
import 'package:nitido/core/presentation/animations/animated_floating_button.dart';
import 'package:nitido/core/presentation/responsive/breakpoints.dart';
import 'package:nitido/core/presentation/widgets/column_with_reorderable_list_and_search.dart';
import 'package:nitido/core/presentation/widgets/nitido_reorderable_list.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

import '../../core/presentation/widgets/no_results.dart';
import '../../core/presentation/widgets/reorderable_drag_icon.dart';

class CategoriesListPage extends StatefulWidget {
  const CategoriesListPage({super.key});

  @override
  State<CategoriesListPage> createState() => _CategoriesListPageState();
}

class _CategoriesListPageState extends State<CategoriesListPage> {
  String searchQuery = '';

  final ScrollController _scrollController = ScrollController();

  void _onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
    });
  }

  void _goToEdit() {
    RouteUtils.pushRoute(const CategoryFormPage());
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PageFramework(
      title: t.general.categories,
      floatingActionButton: BreakPoint.of(context).isLargerThan(BreakpointID.sm)
          ? null
          : AnimatedFloatingButtonBasedOnScroll(
              onPressed: _goToEdit,
              icon: const Icon(Icons.add_rounded),
              scrollController: _scrollController,
              text: t.categories.create,
            ),
      body: ColumnWithReorderableListAndSearch(
        onSearchChanged: _onSearchChanged,
        onAddPressed: _goToEdit,
        addText: t.categories.create,
        child: StreamBuilder(
          stream: CategoryService.instance.getCategories(
            predicate: (acc, curr) =>
                acc.name.contains(searchQuery) & acc.parentCategoryID.isNull(),
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }

            final categories = snapshot.data!;

            if (categories.isEmpty) {
              return NoResults(
                title: t.general.empty_warn,
                noSearchResultsVariation: searchQuery.isNotEmpty,
                description: searchQuery.isNotEmpty
                    ? t.general.search_no_results
                    : '',
              );
            }

            final isOrderEnabled =
                categories.length > 1 && searchQuery.isNullOrEmpty;

            return NitidoReorderableList(
              totalItemCount: categories.length,
              isOrderEnabled: isOrderEnabled,
              scrollController: _scrollController,
              padding: ColumnWithReorderableListAndSearch.listPadding(context),
              spaceBetween: 8,
              itemBuilder: (context, index, isOrdering) {
                final category = categories.elementAt(index);

                return ReorderableListTileStyling(
                  child: ListTile(
                    onTap: () => RouteUtils.pushRoute(
                      CategoryFormPage(categoryUUID: category.id),
                    ),
                    trailing: categories.length > 1
                        ? ReorderableDragIcon(
                            index: index,
                            enabled: isOrderEnabled,
                          )
                        : null,
                    title: Text(
                      category.name,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                    leading: Hero(
                      tag: 'all-accounts-page__account-icon-${category.id}',
                      child: IconDisplayer.fromCategory(
                        context,
                        category: category,
                      ),
                    ),
                  ),
                );
              },
              onReorder: (from, to) async {
                if (to > from) to--;

                final item = categories.removeAt(from);
                categories.insert(to, item);

                await Future.wait(
                  categories.mapIndexed(
                    (index, element) => CategoryService.instance.updateCategory(
                      element.copyWith(displayOrder: index),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
