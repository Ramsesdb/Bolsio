import 'package:flutter/material.dart';
import 'package:bolsio/core/presentation/widgets/number_ui_formatters/decimal_separator.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

/// Tipos lógicos de tecla emitidos por `CalculatorKeypad`. El page los traduce
/// a mutaciones del buffer `_activeExpression` — el widget en sí no conoce el
/// estado.
///
/// Importante: NO se exponen `multiply` ni `divide` (per spec REQ-CALC-2 v1).
/// El engine `evaluateExpression` los soporta, pero la UI v1 mantiene solo
/// suma y resta.
enum KeypadKey {
  digit0,
  digit1,
  digit2,
  digit3,
  digit4,
  digit5,
  digit6,
  digit7,
  digit8,
  digit9,
  decimal,
  backspace,
  clear,
  plus,
  minus,
  equals,
}

/// Keypad numérico de la Calculadora FX (Tanda 3).
///
/// Grid 4×4, layout per `tasks.md` 3.1:
/// ```
/// 7 8 9 ⌫
/// 4 5 6 −
/// 1 2 3 +
/// C 0 sep =
/// ```
///
/// Decimal separator es locale-aware (per spec REQ-CALC-2 "Locale-aware
/// decimal separator"): se lee de `currentDecimalSep` que ya respeta
/// `Intl.defaultLocale`.
///
/// Stateless: cada tecla dispara `onKey(KeypadKey)` y el page mantiene el
/// buffer.
class CalculatorKeypad extends StatelessWidget {
  const CalculatorKeypad({super.key, required this.onKey});

  /// Callback invocado al pulsar una tecla. El page traduce la `KeypadKey` a
  /// mutación del buffer `_activeExpression`.
  final ValueChanged<KeypadKey> onKey;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final decimalSep = currentDecimalSep;

    // Grid 4 columns × 4 rows. Cada celda es un `_KeypadCell` con su tipo:
    //   * digit/decimal/zero      → _CellKind.digit (default look)
    //   * backspace/clear/plus/minus → _CellKind.action (subtle accent)
    //   * equals                  → _CellKind.primary (accent fuerte)
    final rows = <List<_CellSpec>>[
      [
        _CellSpec.digit(KeypadKey.digit7, '7', t.calculator.keypad.a11y.digit_n(n: '7')),
        _CellSpec.digit(KeypadKey.digit8, '8', t.calculator.keypad.a11y.digit_n(n: '8')),
        _CellSpec.digit(KeypadKey.digit9, '9', t.calculator.keypad.a11y.digit_n(n: '9')),
        _CellSpec.action(
          KeypadKey.backspace,
          icon: Icons.backspace_outlined,
          a11y: t.calculator.keypad.a11y.backspace,
        ),
      ],
      [
        _CellSpec.digit(KeypadKey.digit4, '4', t.calculator.keypad.a11y.digit_n(n: '4')),
        _CellSpec.digit(KeypadKey.digit5, '5', t.calculator.keypad.a11y.digit_n(n: '5')),
        _CellSpec.digit(KeypadKey.digit6, '6', t.calculator.keypad.a11y.digit_n(n: '6')),
        _CellSpec.action(
          KeypadKey.minus,
          label: '−',
          a11y: t.calculator.keypad.a11y.minus,
        ),
      ],
      [
        _CellSpec.digit(KeypadKey.digit1, '1', t.calculator.keypad.a11y.digit_n(n: '1')),
        _CellSpec.digit(KeypadKey.digit2, '2', t.calculator.keypad.a11y.digit_n(n: '2')),
        _CellSpec.digit(KeypadKey.digit3, '3', t.calculator.keypad.a11y.digit_n(n: '3')),
        _CellSpec.action(
          KeypadKey.plus,
          label: '+',
          a11y: t.calculator.keypad.a11y.plus,
        ),
      ],
      [
        _CellSpec.action(
          KeypadKey.clear,
          label: 'C',
          a11y: t.calculator.keypad.a11y.clear,
        ),
        _CellSpec.digit(KeypadKey.digit0, '0', t.calculator.keypad.a11y.digit_n(n: '0')),
        _CellSpec.digit(
          KeypadKey.decimal,
          decimalSep,
          t.calculator.keypad.a11y.decimal,
        ),
        _CellSpec.primary(
          KeypadKey.equals,
          label: '=',
          a11y: t.calculator.keypad.a11y.equals,
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  for (final cell in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _KeypadCell(
                          spec: cell,
                          onPressed: () => onKey(cell.key),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Categoría visual de la celda — controla el color de fondo y el énfasis.
enum _CellKind { digit, action, primary }

class _CellSpec {
  const _CellSpec._({
    required this.key,
    required this.kind,
    required this.a11y,
    this.label,
    this.icon,
  });

  factory _CellSpec.digit(KeypadKey key, String label, String a11y) =>
      _CellSpec._(key: key, kind: _CellKind.digit, label: label, a11y: a11y);

  factory _CellSpec.action(
    KeypadKey key, {
    String? label,
    IconData? icon,
    required String a11y,
  }) => _CellSpec._(
    key: key,
    kind: _CellKind.action,
    label: label,
    icon: icon,
    a11y: a11y,
  );

  factory _CellSpec.primary(
    KeypadKey key, {
    required String label,
    required String a11y,
  }) =>
      _CellSpec._(key: key, kind: _CellKind.primary, label: label, a11y: a11y);

  final KeypadKey key;
  final _CellKind kind;
  final String? label;
  final IconData? icon;
  final String a11y;
}

/// Una celda táctil del grid. El color sale exclusivamente de
/// `Theme.of(context).colorScheme` (per instrucción "accent dinámico" — sin
/// hex hardcodeado).
class _KeypadCell extends StatelessWidget {
  const _KeypadCell({required this.spec, required this.onPressed});

  final _CellSpec spec;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Color background;
    final Color foreground;
    switch (spec.kind) {
      case _CellKind.digit:
        background = colors.surfaceContainerHighest.withValues(alpha: 0.55);
        foreground = colors.onSurface;
        break;
      case _CellKind.action:
        background = colors.primaryContainer.withValues(alpha: 0.6);
        foreground = colors.onPrimaryContainer;
        break;
      case _CellKind.primary:
        background = colors.primary;
        foreground = colors.onPrimary;
        break;
    }

    final child = spec.icon != null
        ? Icon(spec.icon, color: foreground, size: 22)
        : Text(
            spec.label ?? '',
            style: textTheme.titleLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          );

    return Semantics(
      button: true,
      label: spec.a11y,
      child: SizedBox(
        height: 56,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
