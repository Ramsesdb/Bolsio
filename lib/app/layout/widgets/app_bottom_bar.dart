import 'package:flutter/material.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/routes/destinations.dart';
import 'package:wallex/core/utils/unique_app_widgets_keys.dart';

/// Bottom navigation bar used in mobile layout.
///
/// Shows a badge on the Transactions tab when there are pending auto-imports.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.selectedDestination});

  final AppMenuDestinationsID selectedDestination;

  @override
  Widget build(BuildContext context) {
    final menuItems = getDestinations(context);

    int selectedNavItemIndex = menuItems.indexWhere(
      (element) => element.id == selectedDestination,
    );

    if (!(0 <= selectedNavItemIndex &&
        selectedNavItemIndex < menuItems.length)) {
      selectedNavItemIndex = menuItems.indexWhere(
        (element) => element.id == AppMenuDestinationsID.settings,
      );

      if (selectedNavItemIndex < 0) {
        selectedNavItemIndex = 0;
      }
    }

    return StreamBuilder<int>(
      stream: PendingImportService.instance.watchPendingCount(),
      initialData: 0,
      builder: (context, snapshot) {
        final pendingCount = snapshot.data ?? 0;

        return NavigationBar(
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHigh,
          indicatorColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          destinations: menuItems.map((e) {
            if (e.id == AppMenuDestinationsID.transactions &&
                pendingCount > 0) {
              return NavigationDestination(
                icon: Badge.count(
                  count: pendingCount,
                  child: Icon(e.icon),
                ),
                selectedIcon: Badge.count(
                  count: pendingCount,
                  child: Icon(e.selectedIcon ?? e.icon),
                ),
                label: e.label,
              );
            }
            return e.toNavigationDestinationWidget(context);
          }).toList(),
          selectedIndex: selectedNavItemIndex,
          onDestinationSelected: (e) => tabsPageKey.currentState
              ?.changePage(menuItems.elementAt(e).id),
        );
      },
    );
  }
}
