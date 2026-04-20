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
