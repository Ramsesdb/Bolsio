import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallex/core/routes/destinations.dart';
import 'package:wallex/core/utils/unique_app_widgets_keys.dart';

class HandleWillPopScope extends StatefulWidget {
  const HandleWillPopScope({required this.child, super.key});
  final Widget child;

  @override
  State<HandleWillPopScope> createState() => _HandleWillPopScopeState();
}

class _HandleWillPopScopeState extends State<HandleWillPopScope> {
  DateTime? _lastBackPressAt;
  Timer? _resetTimer;

  static const _exitWindow = Duration(seconds: 2);

  bool get _nestedCanPop => navigatorKey.currentState?.canPop() ?? false;

  /// True when a route is mounted on the OUTER root navigator above the
  /// app's home (e.g. a modal opened with `useRootNavigator: true`, like the
  /// voice review sheet or any picker spawned from it). Those routes are
  /// invisible to the inner [navigatorKey], so the default back-button
  /// handling below would skip past them and pop a tab page underneath
  /// instead. We must dismiss them first.
  bool get _rootCanPop => rootNavigatorKey.currentState?.canPop() ?? false;

  AppMenuDestinationsID? get _selectedDestination =>
      tabsPageKey.currentState?.selectedDestination;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _armExitWindow() {
    _lastBackPressAt = DateTime.now();
    _resetTimer?.cancel();
    _resetTimer = Timer(_exitWindow, () {
      if (!mounted) return;
      _lastBackPressAt = null;
    });
  }

  bool _withinExitWindow() {
    final at = _lastBackPressAt;
    if (at == null) return false;
    return DateTime.now().difference(at) <= _exitWindow;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final destinationBefore = _selectedDestination;

        // Root-navigator-mounted routes (modals/dialogs/sheets opened with
        // useRootNavigator: true) live ABOVE the inner navigator and must
        // be popped first. Otherwise back would silently pop something
        // underneath them on the inner stack while the modal stays on
        // screen — exactly the "back button does nothing" symptom seen
        // with the voice review sheet's category picker.
        if (_rootCanPop) {
          await rootNavigatorKey.currentState!.maybePop();
          return;
        }

        if (_nestedCanPop) {
          await navigatorKey.currentState!.maybePop();
          return;
        }

        if (destinationBefore == AppMenuDestinationsID.transactions &&
            transactionsPageKey.currentState?.canPop == false) {
          return;
        }

        if (destinationBefore != null &&
            destinationBefore != AppMenuDestinationsID.dashboard) {
          tabsPageKey.currentState?.changePage(AppMenuDestinationsID.dashboard);
          return;
        }

        if (_withinExitWindow()) {
          _resetTimer?.cancel();
          _lastBackPressAt = null;
          await SystemNavigator.pop();
          return;
        }

        _armExitWindow();

        final messenger =
            ScaffoldMessenger.maybeOf(context) ?? snackbarKey.currentState;
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              duration: _exitWindow,
              content: Text('Press again to exit'),
            ),
          );
      },
      child: widget.child,
    );
  }
}
