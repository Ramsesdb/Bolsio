import 'package:flutter/material.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/models/currency/currency_mode.dart';
import 'package:kilatex/core/presentation/widgets/currency_selector_modal.dart';

/// Pure value object describing the on-disk write set that
/// [persistCurrencyModeChange] will apply for a given mode change.
///
/// Exposed so that unit tests can exercise the resolved-decision-#2 rule
/// ("`secondaryCurrency` is PRESERVED on Dual → Single switch") without
/// having to boot a Drift DB or instantiate [UserSettingService].
///
/// Field semantics (each is independently optional — `null` means "do NOT
/// touch the existing row"):
///   - [currencyMode]      : always written; the target mode's `dbValue`.
///   - [preferredCurrency] : always written; the primary ISO code.
///   - [secondaryCurrency] : ONLY written when the new mode is `dual`;
///                            on `single_*` we LEAVE the existing row in
///                            place so re-entering Dual proposes the
///                            previously-chosen pair as default.
///   - [preferredRateSource]: written ONLY when the new mode is `dual`
///                            AND the unordered pair is exactly USD+VES
///                            (the BCV/Paralelo gating). For any other
///                            pair we leave the existing row alone — it
///                            is silently ignored at read time when the
///                            policy doesn't ask for the chip.
class CurrencyModeWrites {
  const CurrencyModeWrites({
    required this.currencyMode,
    required this.preferredCurrency,
    this.secondaryCurrency,
    this.preferredRateSource,
  });

  final String currencyMode;
  final String preferredCurrency;
  final String? secondaryCurrency;
  final String? preferredRateSource;

  /// Whether this write set will touch [SettingKey.secondaryCurrency].
  /// Used by tests to assert the preservation rule (Dual → Single MUST
  /// leave the row alone, so [shouldWriteSecondary] MUST be `false`).
  bool get shouldWriteSecondary => secondaryCurrency != null;

  /// Whether this write set will touch [SettingKey.preferredRateSource].
  bool get shouldWriteRateSource => preferredRateSource != null;

  @override
  bool operator ==(Object other) =>
      other is CurrencyModeWrites &&
      other.currencyMode == currencyMode &&
      other.preferredCurrency == preferredCurrency &&
      other.secondaryCurrency == secondaryCurrency &&
      other.preferredRateSource == preferredRateSource;

  @override
  int get hashCode => Object.hash(
        currencyMode,
        preferredCurrency,
        secondaryCurrency,
        preferredRateSource,
      );

  @override
  String toString() => 'CurrencyModeWrites('
      'mode=$currencyMode, '
      'primary=$preferredCurrency, '
      'secondary=$secondaryCurrency, '
      'rateSource=$preferredRateSource)';
}

/// Compute the on-disk write set for a mode change WITHOUT touching the
/// database. The widget layer calls this and then calls
/// [persistCurrencyModeChange] to actually flush the writes.
///
/// Resolved decision #2 ("`secondaryCurrency` preserved on Dual → Single
/// switch") is enforced HERE — when [newMode] is a `single_*` variant we
/// return [CurrencyModeWrites.secondaryCurrency] = `null`, which means
/// "do NOT touch the existing on-disk row". The previously-chosen
/// secondary stays in `userSettings`, and the resolver simply ignores it
/// (per spec: "MUST ignorar `secondaryCurrency` cuando el modo no es
/// `dual`"). When the user later picks Dual again the in-memory selector
/// re-proposes that value as the default secondary.
///
/// Spec invariant for task 5.3 ("mode change MUST NOT alter accounts or
/// transactions"): this helper only ever returns settings — there is no
/// path from here to the accounts/transactions tables.
CurrencyModeWrites computeModeWrites({
  required CurrencyMode newMode,
  required String primary,
  required String? secondary,
  required String? selectedRateSource,
}) {
  final upperPrimary = primary.toUpperCase();
  final upperSecondary = secondary?.toUpperCase();

  switch (newMode) {
    case CurrencyMode.single_usd:
      return CurrencyModeWrites(
        currencyMode: newMode.dbValue,
        preferredCurrency: 'USD',
        // secondary intentionally NULL → preservation rule.
      );
    case CurrencyMode.single_bs:
      return CurrencyModeWrites(
        currencyMode: newMode.dbValue,
        preferredCurrency: 'VES',
        // secondary intentionally NULL → preservation rule.
      );
    case CurrencyMode.single_other:
      return CurrencyModeWrites(
        currencyMode: newMode.dbValue,
        preferredCurrency: upperPrimary,
        // secondary intentionally NULL → preservation rule.
      );
    case CurrencyMode.dual:
      // Dual MUST always carry a secondary. Defaults to VES if none
      // was chosen explicitly (matches the onboarding default and the
      // migration heuristic).
      final effectiveSecondary = upperSecondary ?? 'VES';
      // BCV/Paralelo gating: only write `preferredRateSource` when the
      // pair is unordered USD+VES. For any other dual pair the chip is
      // hidden and the value is irrelevant.
      final pair = <String>{upperPrimary, effectiveSecondary};
      final isUsdVes = pair.length == 2 &&
          pair.containsAll(<String>{'USD', 'VES'});
      return CurrencyModeWrites(
        currencyMode: newMode.dbValue,
        preferredCurrency: upperPrimary,
        secondaryCurrency: effectiveSecondary,
        preferredRateSource: isUsdVes ? selectedRateSource : null,
      );
  }
}

/// Persist the write set computed by [computeModeWrites].
///
/// This is the ONLY function in the rework that mutates `userSettings`
/// for a mode change. By design it touches NO other table — see the
/// spec invariant in [computeModeWrites].
Future<void> persistCurrencyModeChange(CurrencyModeWrites writes) async {
  final svc = UserSettingService.instance;
  // Ordered so a downstream stream listener sees mode → primary →
  // secondary → rateSource (matches the resolver's combine signature
  // and avoids a transient inconsistent emission window).
  await svc.setItem(SettingKey.currencyMode, writes.currencyMode);
  await svc.setItem(SettingKey.preferredCurrency, writes.preferredCurrency);
  if (writes.shouldWriteSecondary) {
    await svc.setItem(SettingKey.secondaryCurrency, writes.secondaryCurrency);
  }
  if (writes.shouldWriteRateSource) {
    await svc.setItem(
      SettingKey.preferredRateSource,
      writes.preferredRateSource,
    );
  }
}

/// Open the 4-mode currency-mode picker as a bottom sheet rooted on
/// [context]. Mirrors the onboarding s02 visual pattern in spirit, but
/// uses the standard Material [ListTile] vocabulary so it slots into the
/// rest of the [CurrencyManagerPage] settings vocabulary without
/// dragging the V3 onboarding tokens into the production settings UI.
///
/// Resolves with the user's choice (or `null` if dismissed). The dual
/// flow takes the user through one or two follow-up [CurrencySelectorModal]
/// pickers in-place; `single_other` similarly opens the picker in-place
/// before resolving.
Future<CurrencyModeChoice?> showCurrencyModePicker({
  required BuildContext context,
  required CurrencyMode currentMode,
  required String currentPrimary,
  required String? currentSecondary,
}) {
  return showModalBottomSheet<CurrencyModeChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _CurrencyModePickerSheet(
      currentMode: currentMode,
      currentPrimary: currentPrimary,
      currentSecondary: currentSecondary,
    ),
  );
}

/// User's resolved choice from [showCurrencyModePicker]. Carries every
/// value the caller needs to feed [computeModeWrites].
class CurrencyModeChoice {
  const CurrencyModeChoice({
    required this.mode,
    required this.primary,
    this.secondary,
  });

  final CurrencyMode mode;
  final String primary;
  final String? secondary;
}

class _CurrencyModePickerSheet extends StatefulWidget {
  const _CurrencyModePickerSheet({
    required this.currentMode,
    required this.currentPrimary,
    required this.currentSecondary,
  });

  final CurrencyMode currentMode;
  final String currentPrimary;
  final String? currentSecondary;

  @override
  State<_CurrencyModePickerSheet> createState() =>
      _CurrencyModePickerSheetState();
}

class _CurrencyModePickerSheetState extends State<_CurrencyModePickerSheet> {
  late CurrencyMode _mode;
  late String _primary;
  late String? _secondary;

  @override
  void initState() {
    super.initState();
    _mode = widget.currentMode;
    _primary = widget.currentPrimary;
    // Preserve the previously-selected secondary so re-entering Dual
    // proposes it as the default pair (resolved decision #2).
    _secondary = widget.currentSecondary;
  }

  void _selectSingleUsd() {
    setState(() {
      _mode = CurrencyMode.single_usd;
      _primary = 'USD';
    });
  }

  void _selectSingleBs() {
    setState(() {
      _mode = CurrencyMode.single_bs;
      _primary = 'VES';
    });
  }

  Future<void> _selectSingleOther() async {
    showCurrencySelectorModal(
      context,
      CurrencySelectorModal(
        onCurrencySelected: (currency) {
          if (!mounted) return;
          setState(() {
            _mode = CurrencyMode.single_other;
            _primary = currency.code;
          });
        },
      ),
    );
  }

  void _selectDual() {
    setState(() {
      _mode = CurrencyMode.dual;
      // If we are coming from a single mode, prefer USD as the primary
      // unless the user already had a primary that pairs nicely. Default
      // pair USD+VES per design.
      if (widget.currentMode != CurrencyMode.dual) {
        _primary = 'USD';
        _secondary = _secondary ?? 'VES';
      } else {
        _secondary ??= 'VES';
      }
    });
  }

  Future<void> _pickDualPrimary() async {
    showCurrencySelectorModal(
      context,
      CurrencySelectorModal(
        onCurrencySelected: (currency) {
          if (!mounted) return;
          setState(() {
            _mode = CurrencyMode.dual;
            _primary = currency.code;
          });
        },
      ),
    );
  }

  Future<void> _pickDualSecondary() async {
    showCurrencySelectorModal(
      context,
      CurrencySelectorModal(
        onCurrencySelected: (currency) {
          if (!mounted) return;
          setState(() {
            _mode = CurrencyMode.dual;
            _secondary = currency.code;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDual = _mode == CurrencyMode.dual;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Modo de moneda',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Cambia cómo se muestran los totales en el dashboard. '
                  'Tus cuentas y transacciones no se modifican.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      _ModeOptionTile(
                        leadingCode: 'USD',
                        title: 'Solo USD',
                        subtitle: 'Totales en USD.',
                        selected: _mode == CurrencyMode.single_usd,
                        onTap: _selectSingleUsd,
                      ),
                      _ModeOptionTile(
                        leadingCode: 'VES',
                        title: 'Solo Bs',
                        subtitle: 'Totales en Bs.',
                        selected: _mode == CurrencyMode.single_bs,
                        onTap: _selectSingleBs,
                      ),
                      _ModeOptionTile(
                        leadingCode: '★',
                        title: 'Solo otra moneda',
                        subtitle: _mode == CurrencyMode.single_other
                            ? 'Moneda actual: $_primary. Toca para cambiar.'
                            : 'Elige cualquier moneda del catálogo.',
                        selected: _mode == CurrencyMode.single_other,
                        onTap: _selectSingleOther,
                      ),
                      _ModeOptionTile(
                        leadingCode: '↕',
                        title: 'Dual',
                        subtitle:
                            'Dos monedas a la vez. Por defecto USD/Bs.',
                        selected: _mode == CurrencyMode.dual,
                        onTap: _selectDual,
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: isDual
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  4,
                                  20,
                                  4,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 8,
                                        bottom: 6,
                                      ),
                                      child: Text(
                                        'Monedas del par',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    _DualRow(
                                      label: 'Principal',
                                      code: _primary,
                                      onTap: _pickDualPrimary,
                                    ),
                                    const SizedBox(height: 6),
                                    _DualRow(
                                      label: 'Secundaria',
                                      code: _secondary ?? 'VES',
                                      onTap: _pickDualSecondary,
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop(
                              CurrencyModeChoice(
                                mode: _mode,
                                primary: _primary,
                                secondary: _mode == CurrencyMode.dual
                                    ? (_secondary ?? 'VES')
                                    : _secondary,
                              ),
                            );
                          },
                          child: const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeOptionTile extends StatelessWidget {
  const _ModeOptionTile({
    required this.leadingCode,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String leadingCode;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.08)
              : colors.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                leadingCode,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected ? colors.primary : colors.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _DualRow extends StatelessWidget {
  const _DualRow({
    required this.label,
    required this.code,
    required this.onTap,
  });

  final String label;
  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    code,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.expand_more,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
