import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/models/currency/currency.dart';
import 'package:nitido/core/presentation/widgets/currency_selector_modal.dart';
import 'package:nitido/core/services/rate_providers/manual_override_provider.dart';

/// Phase 5 task 5.4 — UI entry point that lets the user set or edit the
/// manual override rate for a currency pair.
///
/// The actual write goes through [ManualOverrideProvider.setManualRate]
/// (which Phase 4 created). The fallback chain in
/// `lib/core/services/rate_providers/rate_provider_chain.dart` already
/// honours the manual row when present — Phase 5 just provides the UI to
/// produce / edit those rows.
///
/// Storage convention (mirrors `CurrencyManagerPage.addExchangeRate` and
/// the `RateProviderChain.setManualRate` resolution):
///   - The user types "1 [from] = X [to]".
///   - The DB row stores `currencyCode = [non-base half]` with the rate
///     expressed as "1 [non-base] = Y [preferred]".
///   - `[preferred]` is `appStateSettings[SettingKey.preferredCurrency]`;
///     this is what every existing reader expects (see
///     `ExchangeRateService.calculateExchangeRate`).
class ManualOverrideDialog extends StatefulWidget {
  const ManualOverrideDialog({
    super.key,
    this.initialCurrency,
  });

  /// Optional preselected currency for the "from" side of the pair. When
  /// the user opens this dialog by tapping a row in the rates list we pass
  /// the row's currency so the form starts in edit mode rather than blank.
  final Currency? initialCurrency;

  @override
  State<ManualOverrideDialog> createState() => _ManualOverrideDialogState();
}

class _ManualOverrideDialogState extends State<ManualOverrideDialog> {
  final TextEditingController _rateController = TextEditingController();
  final FocusNode _rateFocus = FocusNode();
  Currency? _fromCurrency;
  bool _saving = false;
  String? _errorText;

  String get _preferredCurrency =>
      appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

  @override
  void initState() {
    super.initState();
    _fromCurrency = widget.initialCurrency;
  }

  @override
  void dispose() {
    _rateController.dispose();
    _rateFocus.dispose();
    super.dispose();
  }

  Future<void> _pickFromCurrency() async {
    showCurrencySelectorModal(
      context,
      CurrencySelectorModal(
        preselectedCurrency: _fromCurrency,
        onCurrencySelected: (currency) {
          if (!mounted) return;
          setState(() {
            _fromCurrency = currency;
            _errorText = null;
          });
        },
      ),
    );
  }

  Future<void> _save() async {
    final from = _fromCurrency;
    if (from == null) {
      setState(() => _errorText = 'Elige la moneda del par.');
      return;
    }
    if (from.code == _preferredCurrency) {
      setState(
        () => _errorText =
            'La moneda del par no puede ser igual a la moneda preferida.',
      );
      return;
    }
    final raw = _rateController.text.trim().replaceAll(',', '.');
    final rate = double.tryParse(raw);
    if (rate == null || rate <= 0) {
      setState(() => _errorText = 'Ingresa una tasa válida (> 0).');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      // Store as "1 [from.code] = rate [preferredCurrency]" — this is the
      // canonical convention used by the rest of the codebase (see
      // `ExchangeRateService` callers and `addExchangeRate` in
      // `currency_manager.dart`).
      await ManualOverrideProvider.instance.setManualRate(
        currencyCode: from.code,
        rate: rate,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = 'Error al guardar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = _fromCurrency;
    final pref = _preferredCurrency;

    return AlertDialog(
      title: const Text('Tasa manual'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Define una tasa manual. Sobrescribe cualquier valor '
              'automático para esta moneda.',
            ),
            const SizedBox(height: 16),
            Text(
              'Par',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _saving ? null : _pickFromCurrency,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Elige una moneda…',
                  enabled: !_saving,
                ),
                child: Text(
                  from == null
                      ? 'Toca para elegir'
                      : '${from.code} → $pref',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              from == null
                  ? '1 [moneda] = ? $pref'
                  : '1 ${from.code} = ? $pref',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _rateController,
              focusNode: _rateFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              enabled: !_saving,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ej: 40.5',
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Helper: open the manual-override dialog and return whether the user
/// saved a new manual rate. Returns `true` only when the dialog popped
/// with a successful save.
Future<bool> showManualOverrideDialog(
  BuildContext context, {
  Currency? initialCurrency,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => ManualOverrideDialog(initialCurrency: initialCurrency),
  );
  return result == true;
}
