import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';

/// Standard scaffold for every v3 onboarding slide.
///
/// Layout:
/// - Scrollable body (padding 24) containing [child]
/// - Bottom action area with a primary CTA and optional secondary CTA
///
/// The slide provides no AppBar. The progress bar and any back button are
/// rendered by the parent [OnboardingPage] so they stay fixed across slide
/// transitions.
class V3SlideTemplate extends StatelessWidget {
  const V3SlideTemplate({
    super.key,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryEnabled = true,
    this.secondaryLabel,
    this.onSecondary,
  });

  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              V3Tokens.space24,
              V3Tokens.space16,
              V3Tokens.space24,
              V3Tokens.space24,
            ),
            child: child,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            V3Tokens.space24,
            0,
            V3Tokens.space24,
            V3Tokens.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: primaryEnabled ? onPrimary : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: V3Tokens.space16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
                  ),
                ),
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: V3Tokens.spaceMd),
                TextButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
