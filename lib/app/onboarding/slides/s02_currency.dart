import 'package:flutter/material.dart';
import 'package:nitido/app/onboarding/theme/v3_tokens.dart';
import 'package:nitido/app/onboarding/widgets/v3_currency_tile.dart';
import 'package:nitido/app/onboarding/widgets/v3_slide_template.dart';
import 'package:nitido/core/models/currency/currency_mode.dart';
import 'package:nitido/core/presentation/widgets/currency_selector_modal.dart';

/// Slide 2 — currency mode selection.
///
/// Presents the four official currency modes per spec
/// `currency-modes-rework/specs/onboarding/spec.md` (in this exact order):
///
/// 1. `single_usd` — dashboard shows ONE line in USD.
/// 2. `single_bs`  — dashboard shows ONE line in VES.
/// 3. `single_other` — opens [CurrencySelectorModal] (151 currencies). The
///    selected ISO code becomes `preferredCurrency`.
/// 4. `dual` — two-line dashboard. Defaults to (`USD`, `VES`); both pickers
///    open the same [CurrencySelectorModal] for full-catalog override.
///
/// The slide owns no persistence — it only emits the choice tuple
/// (`mode`, `primary`, `secondary?`) up to [OnboardingPage] via [onChange].
/// The parent stores the values in lifted state and writes them to
/// [UserSettingService] in `_applyChoices()` (see `onboarding.dart`).
class Slide02Currency extends StatefulWidget {
  const Slide02Currency({
    super.key,
    required this.mode,
    required this.primaryCurrency,
    required this.secondaryCurrency,
    required this.onChange,
    required this.onNext,
    this.onSkip,
  });

  /// Currently selected mode — drives the tile selection state.
  final CurrencyMode mode;

  /// Primary currency ISO code held by the parent. For `single_*` modes
  /// this is the user's chosen currency; for `dual` it is the primary
  /// (defaults to `'USD'`).
  final String primaryCurrency;

  /// Secondary currency ISO code, only meaningful when [mode] is
  /// [CurrencyMode.dual]. `null` for single modes.
  final String? secondaryCurrency;

  /// Emits the new tuple whenever the user taps a tile or completes a
  /// modal selection. The parent updates lifted state and triggers a
  /// rebuild — the slide list re-renders so s03 inclusion reflects the
  /// new mode/pair without manual index recompute.
  final void Function(
    CurrencyMode mode,
    String primaryCurrency,
    String? secondaryCurrency,
  ) onChange;

  final VoidCallback onNext;
  final VoidCallback? onSkip;

  @override
  State<Slide02Currency> createState() => _Slide02CurrencyState();
}

class _Slide02CurrencyState extends State<Slide02Currency> {
  void _selectSingleUsd() {
    widget.onChange(CurrencyMode.single_usd, 'USD', null);
  }

  void _selectSingleBs() {
    widget.onChange(CurrencyMode.single_bs, 'VES', null);
  }

  void _selectSingleOther() {
    // Preselection is intentionally null: synthesizing a fake [Currency]
    // here would require loading the catalog (async). The modal opens with
    // no preselection but keyboard search instantly narrows the 151-row list.
    showCurrencySelectorModal(
      context,
      CurrencySelectorModal(
        onCurrencySelected: (currency) {
          widget.onChange(
            CurrencyMode.single_other,
            currency.code,
            null,
          );
        },
      ),
    );
  }

  void _selectDual() {
    // Tap on the Dual tile commits the mode immediately with the current
    // pair (or the spec defaults USD+VES on first tap). The detailed
    // primary/secondary pickers below the tile let the user override
    // either side via the same CurrencySelectorModal.
    final primary = (widget.mode == CurrencyMode.dual)
        ? widget.primaryCurrency
        : 'USD';
    final secondary = (widget.mode == CurrencyMode.dual &&
            widget.secondaryCurrency != null)
        ? widget.secondaryCurrency!
        : 'VES';
    widget.onChange(CurrencyMode.dual, primary, secondary);
  }

  void _pickDualPrimary() {
    showCurrencySelectorModal(
      context,
      CurrencySelectorModal(
        onCurrencySelected: (currency) {
          widget.onChange(
            CurrencyMode.dual,
            currency.code,
            widget.secondaryCurrency ?? 'VES',
          );
        },
      ),
    );
  }

  void _pickDualSecondary() {
    showCurrencySelectorModal(
      context,
      CurrencySelectorModal(
        onCurrencySelected: (currency) {
          widget.onChange(
            CurrencyMode.dual,
            widget.primaryCurrency,
            currency.code,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;

    final isSingleUsd = widget.mode == CurrencyMode.single_usd;
    final isSingleBs = widget.mode == CurrencyMode.single_bs;
    final isSingleOther = widget.mode == CurrencyMode.single_other;
    final isDual = widget.mode == CurrencyMode.dual;

    // Subtitle for the "Otra moneda" tile reflects the current pick when
    // the mode is single_other so the user knows what they chose without
    // re-opening the modal.
    final singleOtherSubtitle = isSingleOther
        ? 'Moneda seleccionada: ${widget.primaryCurrency}. Toca para cambiar.'
        : 'Elige cualquier moneda del catálogo.';

    return V3SlideTemplate(
      primaryLabel: 'Siguiente',
      onPrimary: widget.onNext,
      onSecondary: widget.onSkip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿En qué moneda piensas?',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Tu moneda preferida. La usamos para mostrar totales y presupuestos.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          V3CurrencyTile(
            code: 'USD',
            title: 'Solo USD',
            subtitle: 'Totales en USD. Ideal si ahorras en divisa.',
            selected: isSingleUsd,
            onTap: _selectSingleUsd,
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          V3CurrencyTile(
            code: 'VES',
            title: 'Solo Bs',
            subtitle: 'Totales en Bs. Para gasto diario en Venezuela.',
            selected: isSingleBs,
            onTap: _selectSingleBs,
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          V3CurrencyTile(
            code: '★',
            title: 'Solo otra moneda',
            subtitle: singleOtherSubtitle,
            selected: isSingleOther,
            onTap: _selectSingleOther,
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          V3CurrencyTile(
            code: '↕',
            title: 'Dual',
            subtitle: 'Ambas monedas visibles a la vez. Por defecto USD/Bs.',
            selected: isDual,
            onTap: _selectDual,
          ),

          // Sub-row visible ONLY when the user is in dual mode — lets them
          // override the default (USD, VES) pair with any catalog currency.
          // Stays animated to keep the slide compact for the other modes.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isDual
                ? Padding(
                    padding: const EdgeInsets.only(
                      left: V3Tokens.space16,
                      top: V3Tokens.spaceMd,
                      right: V3Tokens.space16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monedas del par',
                          style: V3Tokens.uiStyle(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _DualCurrencyRow(
                          label: 'Principal',
                          code: widget.primaryCurrency,
                          onTap: _pickDualPrimary,
                        ),
                        const SizedBox(height: 6),
                        _DualCurrencyRow(
                          label: 'Secundaria',
                          code: widget.secondaryCurrency ?? 'VES',
                          onTap: _pickDualSecondary,
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Compact tappable row used inside the dual sub-selector. Shows the
/// label (`Principal` / `Secundaria`) on the left, the current ISO code
/// pill on the right, and opens the full [CurrencySelectorModal] on tap.
class _DualCurrencyRow extends StatelessWidget {
  const _DualCurrencyRow({
    required this.label,
    required this.code,
    required this.onTap,
  });

  final String label;
  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;
    final pillBg = isDark ? V3Tokens.pillBgDark : V3Tokens.pillBgLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: V3Tokens.uiStyle(
                  size: 13,
                  weight: FontWeight.w500,
                  color: mutedColor,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(V3Tokens.radiusPill),
              ),
              child: Row(
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: V3Tokens.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.expand_more, size: 16, color: mutedColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
