import 'package:flutter/material.dart';
import 'package:bolsio/app/onboarding/theme/v3_tokens.dart';
import 'package:bolsio/app/onboarding/widgets/v3_primary_button.dart';
import 'package:bolsio/app/onboarding/widgets/v3_secondary_button.dart';

/// Standard scaffold for every v3 onboarding slide.
///
/// Layout:
/// - Scrollable body (padding 24) containing [child]
/// - Bottom action area with a primary CTA and optional secondary CTA
///
/// The slide provides no AppBar. The progress bar and any back button are
/// rendered by the parent [OnboardingPage] so they stay fixed across slide
/// transitions.
///
/// Buttons use the official v3 components ([V3PrimaryButton] /
/// [V3SecondaryButton]) so visuals match the Anthropic v3 design HTML.
class V3SlideTemplate extends StatelessWidget {
  const V3SlideTemplate({
    super.key,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryEnabled = true,
    this.primaryLeadingIcon = Icons.arrow_forward,
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryLeadingIcon,
  });

  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;

  /// Leading icon for the primary CTA. Defaults to a forward arrow,
  /// matching the official v3 design ("→ Continuar" with the arrow before
  /// the label). Pass `null` to hide.
  final IconData? primaryLeadingIcon;

  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Optional leading icon for the secondary CTA. Use [Icons.arrow_back] for
  /// "back"-style flows; leave `null` for plain "Skip" labels.
  final IconData? secondaryLeadingIcon;

  @override
  Widget build(BuildContext context) {
    // Default to "Omitir" when a skip callback was provided but no explicit
    // label was set. Slides that need a different copy (e.g. s07's
    // "Omitir por ahora") still pass `secondaryLabel` explicitly.
    final String? effectiveSecondaryLabel = (onSecondary != null)
        ? (secondaryLabel ?? 'Omitir')
        : secondaryLabel;

    final bool hasSecondary =
        effectiveSecondaryLabel != null && onSecondary != null;

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
          child: hasSecondary
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: V3SecondaryButton(
                        label: effectiveSecondaryLabel,
                        onPressed: onSecondary,
                        leadingIcon:
                            secondaryLeadingIcon ?? Icons.arrow_forward,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: V3PrimaryButton(
                        label: primaryLabel,
                        onPressed: primaryEnabled ? onPrimary : null,
                        leadingIcon: primaryLeadingIcon,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    V3PrimaryButton(
                      label: primaryLabel,
                      onPressed: primaryEnabled ? onPrimary : null,
                      leadingIcon: primaryLeadingIcon,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
