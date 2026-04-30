import 'package:flutter/material.dart';
import 'package:kilatex/core/presentation/helpers/global_snackbar.dart';
import 'package:kilatex/core/presentation/theme.dart';
import 'package:kilatex/core/utils/logger.dart';
import 'package:kilatex/core/utils/unique_app_widgets_keys.dart';

class SnackbarParams {
  /// The amount of time the snack bar should be displayed.
  ///
  /// Defaults to 4.0s.
  final Duration duration;
  final String title;
  final String? message;
  final List<WallexSnackbarAction>? actions;

  /// Whether to clear all previous snackbars before showing the new one.
  ///
  /// Defaults to true.
  final bool clearPrevious;

  /// Whether to show the snackbar at the top of the screen using global snackbar
  /// or at the bottom using ScaffoldMessenger.
  ///
  /// If null, uses the default defined in [WallexSnackbar.showAtTopDefault].
  final bool? showAtTop;

  SnackbarParams(
    this.title, {
    this.duration = const Duration(seconds: 4),
    this.actions,
    this.message,
    this.showAtTop,
    this.clearPrevious = true,
  });

  SnackbarParams.fromError(
    dynamic errorMessage, {
    this.duration = const Duration(seconds: 6),
    this.actions,
    this.clearPrevious = true,
    this.showAtTop = false,
  }) : title = 'Error',
       message = '$errorMessage';

  EdgeInsetsGeometry get padding => EdgeInsets.only(
    top: actions != null && actions!.isNotEmpty ? 6 : 8,
    bottom: actions != null && actions!.isNotEmpty ? 4 : 8,
    left: 16,
    right: actions != null && actions!.isNotEmpty ? 8 : 16,
  );
}

abstract class WallexSnackbar {
  /// Whether to show snackbars at the top of the screen using global snackbar
  /// or at the bottom using ScaffoldMessenger.
  static bool get showAtTopDefault => false;

  /// Private method to get ScaffoldMessenger and optionally clear previous snackbars
  static ScaffoldMessengerState _getScaffoldMessenger(SnackbarParams options) {
    final scaffoldMessenger = snackbarKey.currentState;

    if (scaffoldMessenger == null || scaffoldMessenger.mounted == false) {
      Logger.printDebug(
        'ScaffoldMessengerState is null. Cannot show snackbar.',
      );
    }

    if (options.clearPrevious) {
      final globalSnackbarState = globalSnackbarKey.currentState;

      if (globalSnackbarState != null &&
          globalSnackbarState.mounted &&
          globalSnackbarState.currentQueue.isNotEmpty) {
        Future.delayed(Duration(milliseconds: 1), () {
          globalSnackbarState.animateOut();
        });
      }

      scaffoldMessenger!.clearSnackBars();
    }

    return scaffoldMessenger!;
  }

  static dynamic openSnackbar({
    required SnackbarParams options,
    required Color bgColor,
    required Color textColor,
    required IconData iconData,
  }) {
    final showAtTop = options.showAtTop ?? WallexSnackbar.showAtTopDefault;

    if (showAtTop) {
      _getScaffoldMessenger(options);

      final snackbarResult = globalSnackbarKey.currentState!.post(
        SnackbarInstance.fromParams(
          options,
          textColor: textColor,
          backgroundColor: bgColor,
          iconData: iconData,
        ),
      );

      return snackbarResult;
    }

    return _getScaffoldMessenger(options).showSnackBar(
      SnackBar(
        padding: options.padding,
        backgroundColor: bgColor,
        //  margin: const EdgeInsets.all(8),
        //  behavior: SnackBarBehavior.floating,
        duration: options.duration,
        content: WallexSnackbarContent(
          title: options.title,
          message: options.message,
          color: textColor,
          icon: iconData,
          actions: options.actions,
        ),
      ),
    );
  }

  static dynamic success(SnackbarParams options) {
    return WallexSnackbar.openSnackbar(
      options: options,
      bgColor: Colors.green[50]!,
      textColor: Colors.green,
      iconData: Icons.check_circle_outline,
    );
  }

  static dynamic error(SnackbarParams options) {
    return WallexSnackbar.openSnackbar(
      options: options,
      bgColor: isAppInLightBrightness(snackbarKey.currentContext!)
          ? Theme.of(snackbarKey.currentContext!).colorScheme.errorContainer
          : Theme.of(snackbarKey.currentContext!).colorScheme.error,
      textColor: isAppInLightBrightness(snackbarKey.currentContext!)
          ? Theme.of(snackbarKey.currentContext!).colorScheme.error
          : Theme.of(snackbarKey.currentContext!).colorScheme.errorContainer,
      iconData: Icons.error_outline,
    );
  }

  static dynamic warning(SnackbarParams options) {
    return WallexSnackbar.openSnackbar(
      options: options,
      bgColor: Colors.amber[50]!,
      textColor: Colors.amber,
      iconData: Icons.warning_amber_rounded,
    );
  }

  static dynamic info(SnackbarParams options) {
    return WallexSnackbar.openSnackbar(
      options: options,
      bgColor: Colors.blue[50]!,
      textColor: Colors.blue,
      iconData: Icons.info_outline_rounded,
    );
  }
}

class WallexSnackbarAction {
  final String label;
  final VoidCallback? onPressed;

  WallexSnackbarAction({required this.label, required this.onPressed});
}

class WallexSnackbarContent extends StatelessWidget {
  const WallexSnackbarContent({
    super.key,
    required this.title,
    required this.color,
    this.message,
    this.icon,
    this.actions,
  });

  final Color color;

  /// title is the header String that will show on top
  final String title;

  /// message String is the body message which shows only 2 lines at max
  final String? message;

  /// `optional` color of the SnackBar/MaterialBanner body
  final IconData? icon;

  final List<WallexSnackbarAction>? actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textColor = isAppInDarkBrightness(context)
        ? Theme.of(context).colorScheme.surface
        : Theme.of(context).colorScheme.onSurface;

    return Wrap(
      direction: Axis.horizontal,
      alignment: WrapAlignment.spaceBetween,
      runAlignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      textDirection: TextDirection.ltr,

      children: [
        Row(
          spacing: 12,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, color: color),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyMedium!.copyWith(
                      color: textColor,

                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (message != null)
                    Text(
                      message!,
                      softWrap: true,
                      style: textTheme.bodyMedium!.copyWith(
                        color: textColor.withValues(alpha: 0.9),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),

        if (actions != null && actions!.isNotEmpty)
          Row(
            spacing: 12,
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize:
                (message != null ||
                    actions!.length >= 2 ||
                    title.length > 30 ||
                    actions!.elementAt(0).label.length > 10)
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              ...actions!.map(
                (action) => TextButton(
                  onPressed: action.onPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    textStyle: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  child: Text(action.label),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
