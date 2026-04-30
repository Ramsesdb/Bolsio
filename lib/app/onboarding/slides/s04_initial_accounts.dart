import 'package:flutter/material.dart';
import 'package:bolsio/app/onboarding/bank_options.dart';
import 'package:bolsio/app/onboarding/theme/v3_tokens.dart';
import 'package:bolsio/app/onboarding/widgets/v3_bank_tile.dart';
import 'package:bolsio/app/onboarding/widgets/v3_slide_template.dart';
import 'package:bolsio/app/onboarding/widgets/v3_switch.dart';

class Slide04InitialAccounts extends StatefulWidget {
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
  State<Slide04InitialAccounts> createState() =>
      _Slide04InitialAccountsState();
}

class _Slide04InitialAccountsState extends State<Slide04InitialAccounts> {
  String _query = '';

  List<BankOption> get _filteredBanks {
    if (_query.isEmpty) return kBanks;
    final lower = _query.toLowerCase();
    return kBanks
        .where((b) => b.name.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredBanks;

    return V3SlideTemplate(
      primaryLabel: 'Siguiente',
      onPrimary: widget.onNext,
      onSecondary: widget.onSkip,
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
            'Selecciona los bancos y billeteras que usas. '
            'Creamos las cuentas por ti.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
          ),
          const SizedBox(height: V3Tokens.space16),

          // ── Search field ──────────────────────────────────────────
          TextField(
            onChanged: (v) => setState(() => _query = v),
            style: V3Tokens.uiStyle(
              size: 14,
              weight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar banco o billetera…',
              hintStyle: V3Tokens.uiStyle(
                size: 14,
                weight: FontWeight.w400,
                color: isDark
                    ? V3Tokens.mutedDark
                    : V3Tokens.mutedLight,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: isDark
                    ? V3Tokens.mutedDark
                    : V3Tokens.mutedLight,
              ),
              filled: true,
              fillColor: isDark
                  ? V3Tokens.pillBgDark
                  : V3Tokens.pillBgLight,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  V3Tokens.radiusPill,
                ),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  V3Tokens.radiusPill,
                ),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                  V3Tokens.radiusPill,
                ),
                borderSide: BorderSide(
                  color: V3Tokens.accent.withAlpha(102),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: V3Tokens.space16),

          // ── Bank list ─────────────────────────────────────────────
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: V3Tokens.space24,
              ),
              child: Center(
                child: Text(
                  'No se encontraron resultados',
                  style: V3Tokens.uiStyle(
                    size: 13,
                    weight: FontWeight.w500,
                    color: isDark
                        ? V3Tokens.faintDark
                        : V3Tokens.faintLight,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0) const SizedBox(height: 7),
                  _BankRow(
                    bank: filtered[i],
                    selected: widget.selectedBankIds
                        .contains(filtered[i].id),
                    onTap: () =>
                        widget.onToggleBank(filtered[i].id),
                    showAlsoUsd:
                        widget.currencyMode == 'DUAL' &&
                            filtered[i].supportsBoth &&
                            widget.selectedBankIds
                                .contains(filtered[i].id),
                    alsoUsdValue:
                        widget.alsoUsdForBank[filtered[i].id] ??
                            false,
                    onToggleAlsoUsd: (v) =>
                        widget.onToggleAlsoUsd(
                      filtered[i].id,
                      v,
                    ),
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
