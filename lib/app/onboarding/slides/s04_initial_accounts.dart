import 'package:flutter/material.dart';
import 'package:wallex/app/onboarding/bank_options.dart';
import 'package:wallex/app/onboarding/theme/v3_tokens.dart';
import 'package:wallex/app/onboarding/widgets/v3_bank_tile.dart';
import 'package:wallex/app/onboarding/widgets/v3_slide_template.dart';
import 'package:wallex/app/onboarding/widgets/v3_switch.dart';

class Slide04InitialAccounts extends StatelessWidget {
  const Slide04InitialAccounts({
    super.key,
    required this.selectedBankIds,
    required this.onToggleBank,
    required this.currencyMode,
    required this.alsoUsdForBank,
    required this.onToggleAlsoUsd,
    required this.onNext,
    this.onSkip,
  });

  final Set<String> selectedBankIds;
  final void Function(String id) onToggleBank;

  /// Currency selection from s02 — `'USD'`, `'VES'` or `'DUAL'`. The
  /// per-bank "also USD" sub-row only shows when this is `'DUAL'`.
  final String currencyMode;

  /// Per-bank "also USD" map (key = bank id). Only populated for banks
  /// with `supportsBoth = true` while in DUAL mode.
  final Map<String, bool> alsoUsdForBank;

  final void Function(String bankId, bool value) onToggleAlsoUsd;

  final VoidCallback onNext;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return V3SlideTemplate(
      primaryLabel: 'Siguiente',
      onPrimary: onNext,
      onSecondary: onSkip,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tus cuentas',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            'Selecciona los bancos y billeteras que usas. Creamos las cuentas por ti.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space24),
          // 1-column vertical stack per v3 spec. Cards are gapped 7px
          // (between 6–8 per spec). The parent V3SlideTemplate already
          // provides a SingleChildScrollView, so this Column does not need
          // its own scrolling.
          Column(
            children: [
              for (var i = 0; i < kBanks.length; i++) ...[
                if (i > 0) const SizedBox(height: 7),
                _BankRow(
                  bank: kBanks[i],
                  selected: selectedBankIds.contains(kBanks[i].id),
                  onTap: () => onToggleBank(kBanks[i].id),
                  showAlsoUsd: currencyMode == 'DUAL' &&
                      kBanks[i].supportsBoth &&
                      selectedBankIds.contains(kBanks[i].id),
                  alsoUsdValue: alsoUsdForBank[kBanks[i].id] ?? false,
                  onToggleAlsoUsd: (v) => onToggleAlsoUsd(kBanks[i].id, v),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One row in the bank list: the [V3BankTile] plus an optional, animated
/// "Cuenta en USD también" sub-row that expands/collapses based on
/// [showAlsoUsd]. Kept private to this slide — the sub-row is scoped to
/// onboarding s04 and not reused elsewhere.
class _BankRow extends StatelessWidget {
  const _BankRow({
    required this.bank,
    required this.selected,
    required this.onTap,
    required this.showAlsoUsd,
    required this.alsoUsdValue,
    required this.onToggleAlsoUsd,
  });

  final BankOption bank;
  final bool selected;
  final VoidCallback onTap;
  final bool showAlsoUsd;
  final bool alsoUsdValue;
  final ValueChanged<bool> onToggleAlsoUsd;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? V3Tokens.mutedDark : V3Tokens.mutedLight;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          V3BankTile(
            name: bank.name,
            brandColor: bank.color,
            icon: bank.icon,
            selected: selected,
            onTap: onTap,
          ),
          if (showAlsoUsd)
            Padding(
              padding: const EdgeInsets.only(
                left: 50,
                top: 6,
                bottom: 2,
                right: 4,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cuenta en USD también',
                      style: V3Tokens.uiStyle(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: mutedColor,
                      ),
                    ),
                  ),
                  V3Switch(
                    value: alsoUsdValue,
                    onChanged: onToggleAlsoUsd,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
