import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/number_symbols_data.dart';
import 'package:kilatex/core/models/currency/currency.dart';
import 'package:kilatex/core/presentation/app_colors.dart';

/// Visual pane mostrando una currency + monto display dentro de la
/// `CalculatorPage`.
///
/// Stateless por contrato (per `design.md` § "Plan de archivos"): todo el
/// estado lo gestiona `_CalculatorPageState` y se inyecta a través de los
/// callbacks. La pane se limita a:
///   * mostrar la currency seleccionada (con icono + código)
///   * mostrar el monto formateado (ya formateado por el page)
///   * exponer un picker de currency cuando el usuario tappea el chip
///   * marcar visualmente si es la pane activa (la que recibe keystrokes)
///
/// Tanda 2 introduce esta pane sin keypad ni evaluación de expresión: el
/// `displayValue` que llega del page es el monto crudo (`'0'` por default).
/// Tandas 3+ alimentan `displayValue` con el resultado de
/// `evaluateExpression` y la conversión derivada.
///
/// Polish (Tanda post-MVP):
///   * Cuando la pane es **pasiva** (no recibe keystrokes), el monto se
///     anima con `AnimatedFlipCounter` (rolling digits). La pane **activa**
///     muestra `Text` plano para que cada digit-press se vea instantáneo.
///   * Acepta opcionalmente un widget `trailing` (ej. botón de copiar) que
///     se renderiza al final del row, después del display.
class CurrencyAmountPane extends StatelessWidget {
  const CurrencyAmountPane({
    super.key,
    required this.currency,
    required this.displayValue,
    required this.numericValue,
    required this.isActive,
    required this.availableCurrencies,
    required this.onCurrencyChanged,
    required this.onTap,
    this.trailing,
  });

  /// Currency actualmente mostrada en esta pane.
  final Currency currency;

  /// Valor mostrado, ya formateado por el page (locale-aware downstream).
  /// Se usa SIEMPRE en la pane activa y como fallback en la pasiva si
  /// `numericValue` es `null` (sin tasa).
  final String displayValue;

  /// Valor numérico crudo del monto, para alimentar `AnimatedFlipCounter`
  /// en la pane pasiva. `null` indica "no hay tasa disponible" — se cae al
  /// `displayValue` (que en ese caso es el placeholder `'—'`).
  final double? numericValue;

  /// `true` si esta pane recibe los keystrokes del keypad. La pane activa se
  /// resalta visualmente para guiar al usuario.
  final bool isActive;

  /// Lista de currencies que el `DropdownButton` ofrece. El page la calcula
  /// desde `CurrencyService.instance.getAllCurrencies()` (USD/EUR/USDT/VES +
  /// cualquier currency habilitada por el usuario).
  final List<Currency> availableCurrencies;

  /// Disparado cuando el usuario elige una currency distinta en el picker.
  final ValueChanged<Currency> onCurrencyChanged;

  /// Disparado cuando el usuario tappea el área de la pane (no el picker)
  /// para marcarla como activa.
  final VoidCallback onTap;

  /// Widget opcional que se renderiza al final del row, después del display
  /// (ej. el botón de copiar en la pane convertida).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    final borderColor = isActive ? colors.primary : colors.outlineVariant;
    final borderWidth = isActive ? 2.0 : 1.0;
    final amountColor = isActive ? colors.onSurface : appColors.textBody;
    final amountStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: amountColor,
    );

    // El `AnimatedFlipCounter` se monta SIEMPRE en ambas panes (activa y
    // pasiva) para evitar el remount al swap (que reseteaba el state interno
    // del counter y mataba la transición rolling). En la pane activa usamos
    // `Duration.zero` → updates instantáneos sin rolling distractor mientras
    // el user tipea. En la pasiva usamos 300ms → rolling visible en cambios
    // de source/swap. Cuando `numericValue` es `null` o no-finito (sin tasa)
    // caemos al `Text` plano con el placeholder `'—'`.
    final n = numericValue;
    final canFlip = n != null && n.isFinite;

    final Widget display = canFlip
        ? AnimatedFlipCounter(
            value: n,
            duration:
                isActive ? Duration.zero : const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            fractionDigits: currency.decimalPlaces,
            thousandSeparator: _localeThousandSep(),
            decimalSeparator: _localeDecimalSep(),
            mainAxisAlignment: MainAxisAlignment.end,
            textStyle: amountStyle,
          )
        : Text(
            displayValue,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: amountStyle,
          );

    return Semantics(
      button: true,
      selected: isActive,
      label: '${currency.code} $displayValue',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: isActive
                ? colors.primaryContainer.withValues(alpha: 0.25)
                : colors.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _CurrencyPicker(
                currency: currency,
                availableCurrencies: availableCurrencies,
                onChanged: onCurrencyChanged,
              ),
              const SizedBox(width: 12),
              Expanded(child: Align(alignment: Alignment.centerRight, child: display)),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Decimal separator del locale actual. Reusamos `numberFormatSymbols`
  /// de `intl` (mismo lookup que `currentDecimalSep`).
  String _localeDecimalSep() {
    final locale = Intl.defaultLocale?.replaceAll('-', '_') ?? 'en';
    return numberFormatSymbols[locale]?.DECIMAL_SEP ?? '.';
  }

  /// Thousand separator del locale actual.
  String _localeThousandSep() {
    final locale = Intl.defaultLocale?.replaceAll('-', '_') ?? 'en';
    return numberFormatSymbols[locale]?.GROUP_SEP ?? ',';
  }
}

/// `DropdownButton` estándar (per task 2.1) que lista las currencies
/// disponibles. Encapsulado para no contaminar el árbol del pane con el
/// `DropdownButtonHideUnderline` boilerplate.
class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({
    required this.currency,
    required this.availableCurrencies,
    required this.onChanged,
  });

  final Currency currency;
  final List<Currency> availableCurrencies;
  final ValueChanged<Currency> onChanged;

  @override
  Widget build(BuildContext context) {
    // Si la currency actual no está en `availableCurrencies` (caso edge: el
    // stream aún no resolvió o la currency fue removida), inyectarla para
    // evitar el assert de `DropdownButton` ("Either zero or 2 or more
    // DropdownMenuItems were detected with the same value").
    final items = <Currency>[
      currency,
      ...availableCurrencies.where((c) => c.code != currency.code),
    ];

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: currency.code,
        isDense: true,
        borderRadius: BorderRadius.circular(12),
        items: items
            .map(
              (c) => DropdownMenuItem<String>(
                value: c.code,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: c.displayFlagIcon(size: 22),
                    ),
                    const SizedBox(width: 8),
                    Text(c.code),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (code) {
          if (code == null || code == currency.code) return;
          final selected = items.firstWhere((c) => c.code == code);
          onChanged(selected);
        },
      ),
    );
  }
}
