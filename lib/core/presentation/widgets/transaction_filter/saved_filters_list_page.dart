import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:bolsio/app/layout/page_framework.dart';
import 'package:bolsio/core/database/services/filters/saved_filters_service.dart';
import 'package:bolsio/core/extensions/string.extension.dart';
import 'package:bolsio/core/presentation/animations/animated_floating_button.dart';
import 'package:bolsio/core/presentation/responsive/breakpoints.dart';
import 'package:bolsio/core/presentation/widgets/column_with_reorderable_list_and_search.dart';
import 'package:bolsio/core/presentation/widgets/bolsio_reorderable_list.dart';
import 'package:bolsio/core/presentation/widgets/no_results.dart';
import 'package:bolsio/core/presentation/widgets/reorderable_drag_icon.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/saved_filter_form_page.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

class SavedFiltersListPage extends StatefulWidget {
  const SavedFiltersListPage({super.key});

  @override
  State<SavedFiltersListPage> createState() => _SavedFiltersListPageState();
}

class _SavedFiltersListPageState extends State<SavedFiltersListPage> {
  String searchQuery = '';

  final ScrollController _scrollController = ScrollController();

  void _onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
    });
  }

  void _goToEdit() {
    RouteUtils.pushRoute(const SavedFilterFormPage());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget buildList() {
    final t = Translations.of(context);

    return StreamBuilder(
      stream: SavedFiltersService.instance.getSavedFilters(
        predicate: (savedFilter, filterSet) =>
            savedFilter.name.contains(searchQuery),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }

        if (snapshot.data!.isEmpty) {
          return NoResults(
            title: searchQuery.isNotEmpty
                ? t.general.empty_warn
                : t.transaction.filters.saved.empty_title,
            noSearchResultsVariation: searchQuery.isNotEmpty,
            description: searchQuery.isNotEmpty
                ? t.general.search_no_results
                : t.transaction.filters.saved.empty_description,
          );
        }

        final filters = snapshot.data!;

        final isOrderEnabled = filters.length > 1 && searchQuery.isNullOrEmpty;

        return BolsioReorderableList(
          totalItemCount: filters.length,
          padding: ColumnWithReorderableListAndSearch.listPadding(context),
          scrollController: _scrollController,
          isOrderEnabled: isOrderEnabled,
          spaceBetween: 8,
          itemBuilder: (context, index, isOrdering) {
            final filter = filters.elementAt(index);

            return ReorderableListTileStyling(
              child: ListTile(
                onTap: () => RouteUtils.pushRoute(
                  SavedFilterFormPage(savedFilter: filter),
                ),
                trailing: filters.length > 1
                    ? ReorderableDragIcon(index: index, enabled: isOrderEnabled)
                    : null,
                leading: const Icon(Icons.filter_alt_outlined),
                title: Text(filter.name),
              ),
            );
          },
          onReorder: (from, to) async {
            if (to > from) to--;

            final item = filters.removeAt(from);
            filters.insert(to, item);

            await Future.wait(
              filters.mapIndexed(
                (index, element) => SavedFiltersService.instance
                    .updateSavedFilter(element.copyWith(displayOrder: index)),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final fab = BreakPoint.of(context).isLargerThan(BreakpointID.sm)
        ? null
        : AnimatedFloatingButtonBasedOnScroll(
            onPressed: _goToEdit,
            icon: const Icon(Icons.add_rounded),
            scrollController: _scrollController,
            text: t.ui_actions.add,
          );

    return PageFramework(
      title: t.transaction.filters.saved.title,
      floatingActionButton: fab,
      body: ColumnWithReorderableListAndSearch(
        onSearchChanged: _onSearchChanged,
        onAddPressed: _goToEdit,
        addText: t.ui_actions.add,
        child: buildList(),
      ),
    );
  }
}
