import 'package:flutter/material.dart';
import 'package:kilatex/app/chat/theme/wallex_ai_tokens.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.label});

  final String? label;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: WallexAiTokens.typingBounceDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WallexAiTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.bubbleAi,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(WallexAiTokens.bubbleTailRadius),
          topRight: Radius.circular(WallexAiTokens.bubbleRadius),
          bottomLeft: Radius.circular(WallexAiTokens.bubbleRadius),
          bottomRight: Radius.circular(WallexAiTokens.bubbleRadius),
        ),
        border: Border.all(color: tokens.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 30,
            height: 14,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final progress = _phasedProgress(_controller.value, i);
                    final curved = Curves.easeInOut.transform(progress);
                    final translateY =
                        -_bounceCurve(curved) * WallexAiTokens.typingTranslateY;
                    final opacity = 0.4 + 0.6 * _bounceCurve(curved);
                    return Transform.translate(
                      offset: Offset(0, translateY),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: opacity),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
          if (widget.label != null) ...[
            const SizedBox(width: 10),
            Text(
              widget.label!,
              style: tokens.cardKicker.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _phasedProgress(double value, int index) {
    final staggerRatio = WallexAiTokens.typingStagger.inMilliseconds /
        WallexAiTokens.typingBounceDuration.inMilliseconds;
    final shifted = (value - index * staggerRatio) % 1.0;
    return shifted < 0 ? shifted + 1.0 : shifted;
  }

  double _bounceCurve(double t) {
    if (t < 0.4) return t / 0.4;
    if (t < 0.8) return 1 - (t - 0.4) / 0.4;
    return 0;
  }
}
