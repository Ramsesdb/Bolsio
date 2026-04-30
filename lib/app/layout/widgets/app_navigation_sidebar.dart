import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kilatex/app/layout/widgets/app_navigation_drawer.dart';
import 'package:kilatex/app/layout/window_bar.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/extensions/color.extensions.dart';
import 'package:kilatex/core/presentation/app_colors.dart';
import 'package:kilatex/core/presentation/responsive/breakpoint_container.dart';
import 'package:kilatex/core/presentation/responsive/breakpoints.dart';
import 'package:kilatex/app/common/widgets/user_avatar_display.dart';
import 'package:kilatex/core/routes/destinations.dart';
import 'package:kilatex/core/routes/route_utils.dart';
import 'package:kilatex/core/utils/app_utils.dart';
import 'package:kilatex/core/utils/unique_app_widgets_keys.dart';

/// Returns the appropriate width for the app navigation sidebar based on screen size
double getNavigationSidebarWidth(BuildContext context) {
  final padding = MediaQuery.viewPaddingOf(context).left;

  if (AppUtils.isMobileLayout(context)) {
    return 0;
  } else if (BreakPoint.of(context).isSmallerThan(BreakpointID.xl)) {
    return 108 + padding;
  }

  double screenPercent = 0.3;
  double maxWidthNavigation = 240 + padding;

  return min(
    maxWidthNavigation,
    MediaQuery.sizeOf(context).width * screenPercent,
  );
}

/// Sidebar navigation used in tablet and desktop layouts
class AppNavigationSidebar extends StatefulWidget {
  const AppNavigationSidebar({super.key});

  @override
  State<AppNavigationSidebar> createState() => AppNavigationSidebarState();
}

class AppNavigationSidebarState extends State<AppNavigationSidebar> {
  AppMenuDestinationsID? selectedDestination;

  void setSelectedDestination(AppMenuDestinationsID? destination) {
    setState(() {
      selectedDestination = destination;
    });
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = getDestinations(context);

    selectedDestination ??= menuItems.elementAt(0).id;

    final selectedNavItemIndex = menuItems.indexWhere(
      (element) => element.id == selectedDestination!,
    );

    onDestinationSelected(int e) {
      RouteUtils.popAllRoutesExceptFirst();
      tabsPageKey.currentState?.changePage(menuItems.elementAt(e).id);
    }

    final navSidebarWidth = getNavigationSidebarWidth(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOutCubicEmphasized,
      width: navSidebarWidth,
      child: Builder(
        builder: (context) {
          if (navSidebarWidth == 0) {
            return const SizedBox.shrink();
          }

          return BreakpointContainer(
            xlChild: SideNavigationDrawer(
              drawerActions: menuItems,
              onDestinationSelected: onDestinationSelected,
              selectedIndex: selectedNavItemIndex,
            ),
            child: NavigationRail(
              destinations: menuItems
                  .map((e) => e.toNavigationRailDestinationWidget())
                  .toList(),
              onDestinationSelected: onDestinationSelected,
              leading: const SizedBox(height: 2),
              backgroundColor: getWindowBackgroundColor(context),
              labelType: NavigationRailLabelType.all,
              scrollable: true,
              leadingAtTop: true,
              trailingAtBottom: true,
              selectedIndex: selectedNavItemIndex < 0
                  ? null
                  : selectedNavItemIndex,
              trailing: Container(
                margin: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.bottomCenter,
                child: UserAvatarDisplay(
                  avatar: appStateSettings[SettingKey.avatar],
                  backgroundColor: AppColors.of(
                    context,
                  ).onConsistentPrimary.darken(0.25),
                  border: Border.all(
                    width: 2,
                    color: AppColors.of(context).onConsistentPrimary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
