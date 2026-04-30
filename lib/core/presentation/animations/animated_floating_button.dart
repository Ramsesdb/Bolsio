import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:bolsio/core/presentation/responsive/breakpoints.dart';

class AnimatedFloatingButton extends StatelessWidget {
  const AnimatedFloatingButton({
    super.key,
    this.onPressed,
    required this.icon,
    required this.text,
    required this.isExtended,
  });

  final void Function()? onPressed;
  final Widget icon;
  final String text;

  final bool isExtended;

  static bool shouldExtendButton(
    BuildContext context,
    ScrollController scrollController,
  ) {
    return BreakPoint.of(context).isLargerThan(BreakpointID.md) ||
        scrollController.offset <= 10 ||
        scrollController.position.userScrollDirection !=
            ScrollDirection.reverse;
  }

  @override
  Widget build(BuildContext context) {
    return GlassFab(
      onPressed: onPressed,
      tooltip: isExtended ? null : text,
      icon: icon,
      isExtended: isExtended,
      label: isExtended
          ? Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            )
          : null,
    );
  }
}

/// A premium glassmorphism-styled floating action button that matches the
/// app's dark glass aesthetic.
class GlassFab extends StatelessWidget {
  const GlassFab({
    super.key,
    this.onPressed,
    required this.icon,
    this.label,
    this.tooltip,
    this.isExtended = false,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget? label;
  final String? tooltip;
  final bool isExtended;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    final content = AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconTheme(
            data: const IconThemeData(color: Colors.white, size: 24),
            child: icon,
          ),
          if (label != null && isExtended) ...[
            const SizedBox(width: 8),
            label!,
          ],
        ],
      ),
    );

    Widget button = Material(
      color: Colors.transparent,
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        customBorder: isExtended
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))
            : const CircleBorder(),
        splashColor: primary.withValues(alpha: 0.15),
        highlightColor: primary.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          height: 56,
          padding: isExtended
              ? const EdgeInsets.symmetric(horizontal: 20)
              : const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: 0.65),
                primary.withValues(alpha: 0.4),
              ],
            ),
            border: Border.all(
              color: primary.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.3),
                blurRadius: 16,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: primary.withValues(alpha: 0.1),
                blurRadius: 24,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: content,
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

class AnimatedFloatingButtonBasedOnScroll extends StatefulWidget {
  const AnimatedFloatingButtonBasedOnScroll({
    super.key,
    required this.scrollController,
    this.onPressed,
    required this.icon,
    required this.text,
    this.builder,
  });

  final void Function()? onPressed;
  final Widget icon;
  final String text;
  final Widget Function(BuildContext context, bool isExtended)? builder;

  final ScrollController scrollController;

  @override
  State<AnimatedFloatingButtonBasedOnScroll> createState() =>
      _AnimatedFloatingButtonBasedOnScrollState();
}

class _AnimatedFloatingButtonBasedOnScrollState
    extends State<AnimatedFloatingButtonBasedOnScroll> {
  bool isFloatingButtonExtended = true;

  void _setFloatingButtonState() {
    bool shouldExtendButton =
        BreakPoint.of(context).isLargerThan(BreakpointID.md) ||
        widget.scrollController.offset <= 10 ||
        widget.scrollController.position.userScrollDirection !=
            ScrollDirection.reverse;

    if (isFloatingButtonExtended != shouldExtendButton) {
      setState(() {
        isFloatingButtonExtended = shouldExtendButton;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_setFloatingButtonState);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_setFloatingButtonState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.builder != null) {
      return widget.builder!(context, isFloatingButtonExtended);
    }

    return AnimatedFloatingButton(
      onPressed: widget.onPressed,
      icon: widget.icon,
      text: widget.text,
      isExtended: isFloatingButtonExtended,
    );
  }
}
