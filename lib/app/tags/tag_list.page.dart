import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:bolsio/app/layout/page_framework.dart';
import 'package:bolsio/app/tags/tag_form_page.dart';
import 'package:bolsio/core/database/services/tags/tags_service.dart';
import 'package:bolsio/core/extensions/string.extension.dart';
import 'package:bolsio/core/presentation/animations/animated_floating_button.dart';
import 'package:bolsio/core/presentation/responsive/breakpoints.dart';
import 'package:bolsio/core/presentation/widgets/column_with_reorderable_list_and_search.dart';
import 'package:bolsio/core/presentation/widgets/bolsio_reorderable_list.dart';
import 'package:bolsio/core/presentation/widgets/no_results.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

import '../../core/presentation/widgets/reorderable_drag_icon.dart';

class TagListPage extends StatefulWidget {
  const TagListPage({super.key});

  @override
  State<TagListPage> createState() => _TagListPageState();
}

class _TagListPageState extends State<TagListPage> {
  String searchQuery = '';

  final ScrollController _scrollController = ScrollController();

  void _onSearchChanged(String query) {
    setState(() {
      searchQuery = query;
    });
  }

  void _goToEdit() {
    RouteUtils.pushRoute(const TagFormPage());
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

  Widget buildList() {
    return StreamBuilder(
      stream: TagService.instance.getTags(
        filter: (p0) => p0.name.contains(searchQuery),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }

        if (snapshot.data!.isEmpty) {
          return NoResults(
            title: t.general.empty_warn,
            noSearchResultsVariation: searchQuery.isNotEmpty,
            description: searchQuery.isNotEmpty
                ? t.general.search_no_results
                : t.tags.empty_list,
          );
        }

        final tags = snapshot.data!;

        final isOrderEnabled = tags.length > 1 && searchQuery.isNullOrEmpty;

        return BolsioReorderableList(
          totalItemCount: tags.length,
          padding: ColumnWithReorderableListAndSearch.listPadding(context),
          scrollController: _scrollController,
          isOrderEnabled: isOrderEnabled,
          spaceBetween: 8,
          itemBuilder: (context, index, isOrdering) {
            final tag = tags.elementAt(index);

            return ReorderableListTileStyling(
              child: ListTile(
                onTap: () => RouteUtils.pushRoute(TagFormPage(tag: tag)),
                trailing: tags.length > 1
                    ? ReorderableDragIcon(index: index, enabled: isOrderEnabled)
                    : null,
                leading: tag.displayIcon(),
                title: Text(tag.name),
                subtitle: tag.description != null && tag.description!.isNotEmpty
                    ? Text(
                        tag.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
              ),
            );
          },
          onReorder: (from, to) async {
            if (to > from) to--;

            final item = tags.removeAt(from);
            tags.insert(to, item);

            await Future.wait(
              tags.mapIndexed(
                (index, element) => TagService.instance.updateTag(
                  element.copyWith(displayOrder: index),
                ),
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
            text: t.tags.add,
          );

    return PageFramework(
      title: t.tags.display(n: 10),
      floatingActionButton: fab,
      body: ColumnWithReorderableListAndSearch(
        onSearchChanged: _onSearchChanged,
        onAddPressed: _goToEdit,
        addText: t.tags.add,
        child: buildList(),
      ),
    );
  }
}
