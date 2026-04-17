import 'package:flutter/material.dart';

class FadeIn extends StatefulWidget {
  const FadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 200),
    this.delay,
  });

  final Widget child;
  final Duration duration;
  final Duration? delay;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController animationController = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // TO DISABLE THE ANIMATION:
    // if (!saveBattery) {
    //   _controller.forward();
    // }

    _opacityAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(animationController);

    if (widget.delay != null) {
      Future.delayed(widget.delay!, () {
        if (mounted) {
          animationController.forward();
        }
      });
    } else {
      animationController.forward();
    }
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // if (saveBattery) {
    //   return widget.child;
    // }

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(opacity: _opacityAnimation.value, child: child);
      },
      child: widget.child,
    );
  }
}
