import 'package:flutter/material.dart';
import 'package:nitido/core/database/app_db.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

/// Simple confirmation dialog shown when changing `trackedSince` on an
/// existing account produces a balance delta that is not "dangerous" enough
/// to require typing a confirmation word.
///
/// Pops `true` when the user accepts, `false` (or `null`) otherwise.
class RetroactivePreviewDialog extends StatelessWidget {
  const RetroactivePreviewDialog({
    super.key,
    required this.currentBalance,
    required this.simulatedBalance,
    required this.currency,
  });

  final double currentBalance;
  final double simulatedBalance;
  final CurrencyInDB currency;

  String _fmt(double v) =>
      '${v.toStringAsFixed(currency.decimalPlaces)} ${currency.symbol}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.account.retroactive.preview_title),
      content: Text(
        t.account.retroactive.preview_message(
          current: _fmt(currentBalance),
          simulated: _fmt(simulatedBalance),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.account.retroactive.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.account.retroactive.accept),
        ),
      ],
    );
  }
}

/// Strong confirmation dialog shown when changing `trackedSince` would
/// produce a balance delta large enough to warrant typing a confirmation
/// word (locale-aware: CONFIRMAR / CONFIRM).
///
/// Pops `true` only if the user accepts with the correct word typed,
/// `false` (or `null`) otherwise.
class RetroactiveStrongConfirmDialog extends StatefulWidget {
  const RetroactiveStrongConfirmDialog({
    super.key,
    required this.currentBalance,
    required this.simulatedBalance,
    required this.currency,
  });

  final double currentBalance;
  final double simulatedBalance;
  final CurrencyInDB currency;

  @override
  State<RetroactiveStrongConfirmDialog> createState() =>
      _RetroactiveStrongConfirmDialogState();
}

class _RetroactiveStrongConfirmDialogState
    extends State<RetroactiveStrongConfirmDialog> {
  final _controller = TextEditingController();
  bool _isValid = false;

  String get _requiredWord {
    final isSpanish = LocaleSettings.currentLocale == AppLocale.es;
    return isSpanish ? 'CONFIRMAR' : 'CONFIRM';
  }

  String _fmt(double v) =>
      '${v.toStringAsFixed(widget.currency.decimalPlaces)} ${widget.currency.symbol}';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  void _onChange() {
    final newValid = _controller.text.trim() == _requiredWord;
    if (newValid != _isValid) {
      setState(() => _isValid = newValid);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.account.retroactive.preview_title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.account.retroactive.preview_message(
              current: _fmt(widget.currentBalance),
              simulated: _fmt(widget.simulatedBalance),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t.account.retroactive.strong_confirm_hint,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: _requiredWord,
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            keyboardType: TextInputType.text,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.account.retroactive.cancel),
        ),
        FilledButton(
          onPressed: _isValid ? () => Navigator.of(context).pop(true) : null,
          child: Text(t.account.retroactive.accept),
        ),
      ],
    );
  }
}
