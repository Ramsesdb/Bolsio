import 'package:flutter/material.dart';
import 'package:bolsio/app/layout/page_switcher.dart';
import 'package:bolsio/app/layout/widgets/app_navigation_sidebar.dart';
import 'package:bolsio/app/layout/window_bar.dart';
import 'package:bolsio/core/presentation/helpers/global_snackbar.dart';

final GlobalKey<PageSwitcherState> tabsPageKey = GlobalKey();
final GlobalKey<AppNavigationSidebarState> navigationSidebarKey = GlobalKey();
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<WindowBarState> windowBarKey = GlobalKey<WindowBarState>();
final GlobalKey<ScaffoldMessengerState> snackbarKey =
    GlobalKey<ScaffoldMessengerState>();
final GlobalKey<GlobalSnackbarState> globalSnackbarKey = GlobalKey();
