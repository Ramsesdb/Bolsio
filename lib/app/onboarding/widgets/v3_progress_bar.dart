import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';

/// Segmented 3px progress bar rendered at the top of each slide.
/// Displays one segment per slide; completed segments are filled with
/// the accent color, pending segments use a muted surface color.
class V3ProgressBar extends StatelessWidget {
  const V3ProgressBar({
    super.key,
    required this.currentIndex,
    required this.totalSlides,
  });

  final int currentIndex;
  final int totalSlides;

  @override
  Widget build(BuildContext context) {
    final inactive = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: V3Tokens.space24),
      child: Row(
        children: List.generate(totalSlides, (i) {
          final filled = i <= currentIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: i == totalSlides - 1 ? 0 : V3Tokens.spaceXs / 2,
                left: i == 0 ? 0 : V3Tokens.spaceXs / 2,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: V3Tokens.progressBarHeight,
                decoration: BoxDecoration(
                  color: filled ? V3Tokens.accent : inactive,
                  borderRadius: BorderRadius.circular(V3Tokens.progressBarHeight),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
