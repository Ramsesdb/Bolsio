import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_primary_button.dart';
import 'package:wallex/app/onboarding/widgets/v3_progress_bar.dart';
import 'package:wallex/app/onboarding/widgets/v3_secondary_button.dart';

/// Standard scaffold for every step of the AI setup wizard.
///
/// Mirrors the visual language of `V3SlideTemplate` from the onboarding flow
/// (scrollable body 24px padding, primary + optional secondary CTAs at the
/// bottom) but lives outside `lib/app/onboarding/` and OWNS its own header
/// (back pill + segmented progress bar) instead of relying on a parent
/// `OnboardingPage`.
///
/// The wizard is a self-contained `StatefulWidget` route, not a full-screen
/// onboarding takeover, so it surfaces an `AppBar`-less header with:
/// - back pill (mirrors `_BackPill` from onboarding) on every step except
///   the first.
/// - flush segmented progress bar reflecting `currentStep / totalSteps`.
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryEnabled = true,
    this.primaryLoading = false,
    this.primaryLeadingIcon = Icons.arrow_forward,
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryLeadingIcon,
    this.onBack,
    this.showBack = true,
    this.hideActions = false,
  });

  final int currentStep;
  final int totalSteps;
  final Widget child;

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final bool primaryLoading;
  final IconData? primaryLeadingIcon;

  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final IconData? secondaryLeadingIcon;

  /// Header back pill callback. When `null` AND [showBack] is `true`, the
  /// wizard pops the route — wizard hosts can override to do extra cleanup
  /// (e.g. animate the PageController instead of popping).
  final VoidCallback? onBack;

  /// Whether to render the back pill in the header. Hidden on the first
  /// step (nothing to go back to inside the wizard) and on steps that own
  /// their own navigation (e.g. the testing-in-progress step).
  final bool showBack;

  /// When `true`, the bottom CTA row is hidden entirely. Used by the
  /// testing-in-progress step which auto-advances on success.
  final bool hideActions;

  @override
  Widget build(BuildContext context) {
    final hasSecondary = secondaryLabel != null && onSecondary != null;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FractionallySizedBox(
            widthFactor: screenWidth < 700 ? 1.0 : 700 / screenWidth,
            child: Column(
              children: [
                // Header — back pill + segmented progress bar. Same shape
                // as `OnboardingPage`'s header so the visual carries from
                // onboarding into the wizard.
                Padding(
                  padding: const EdgeInsets.only(
                    top: V3Tokens.space16,
                    bottom: V3Tokens.space16,
                    left: V3Tokens.space24,
                    right: V3Tokens.space24,
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Row(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(-0.3, 0),
                              end: Offset.zero,
                            ).animate(animation);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child: child,
                              ),
                            );
                          },
                          child: showBack
                              ? Padding(
                                  key: const ValueKey('wizard-back-pill'),
                                  padding: const EdgeInsets.only(
                                    right: V3Tokens.spaceMd,
                                  ),
                                  child: _BackPill(
                                    onTap: onBack ??
                                        () => Navigator.of(context).maybePop(),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('wizard-no-back'),
                                ),
                        ),
                        Expanded(
                          child: V3ProgressBar(
                            currentIndex: currentStep,
                            totalSlides: totalSteps,
                            flush: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Body — scrollable, 24px padding (matches V3SlideTemplate).
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

                // Action row — primary + optional secondary, identical to
                // V3SlideTemplate's bottom block.
                if (!hideActions)
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
                                  label: secondaryLabel!,
                                  onPressed: onSecondary,
                                  leadingIcon: secondaryLeadingIcon ??
                                      Icons.arrow_forward,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: V3PrimaryButton(
                                  label: primaryLabel,
                                  onPressed: primaryEnabled ? onPrimary : null,
                                  leadingIcon: primaryLeadingIcon,
                                  loading: primaryLoading,
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
                                loading: primaryLoading,
                              ),
                            ],
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Header back affordance — copy of the onboarding `_BackPill` so the
/// visual matches between the onboarding flow and the wizard.
class _BackPill extends StatelessWidget {
  const _BackPill({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const double size = 36;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? V3Tokens.pillBgDark : V3Tokens.pillBgLight;
    final Color fg = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Icon(
              Icons.arrow_back_ios_new,
              size: 14,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
