import 'package:flutter/material.dart';
import 'package:bolsio/app/chat/theme/bolsio_ai_tokens.dart';

class BolsioAiOrb extends StatefulWidget {
  const BolsioAiOrb({
    super.key,
    required this.size,
    this.showGlow = true,
    this.animated = false,
  });

  final double size;
  final bool showGlow;
  final bool animated;

  @override
  State<BolsioAiOrb> createState() => _BolsioAiOrbState();
}

class _BolsioAiOrbState extends State<BolsioAiOrb>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _controller = AnimationController(
        vsync: this,
        duration: BolsioAiTokens.orbPulseDuration,
        reverseDuration: BolsioAiTokens.orbPulseDuration,
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BolsioAiOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated != oldWidget.animated) {
      _controller?.dispose();
      _controller = null;
      if (widget.animated) {
        _controller = AnimationController(
          vsync: this,
          duration: BolsioAiTokens.orbPulseDuration,
          reverseDuration: BolsioAiTokens.orbPulseDuration,
        )..repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = BolsioAiTokens.of(context);
    final size = widget.size;

    final orb = SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.showGlow)
            OverflowBox(
              maxWidth: size * 2,
              maxHeight: size * 2,
              child: Container(
                width: size * 2,
                height: size * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      tokens.accent.withValues(alpha: 0.25),
                      tokens.accent.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  tokens.accent,
                  tokens.accentDeep,
                  tokens.accent,
                  tokens.accentDeep,
                  tokens.accent,
                ],
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
            ),
          ),
          Container(
            width: size * 0.78,
            height: size * 0.78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.bubbleAi,
            ),
          ),
          Icon(
            Icons.auto_awesome,
            size: size * 0.34,
            color: tokens.accent,
          ),
        ],
      ),
    );

    if (!widget.animated || _controller == null) return orb;

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + 0.04 * _controller!.value,
          child: child,
        );
      },
      child: orb,
    );
  }
}
