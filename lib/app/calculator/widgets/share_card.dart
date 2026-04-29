import 'package:flutter/material.dart';
import 'package:wallex/core/models/currency/currency.dart';

/// Card brandeado que se renderiza off-screen y se captura como PNG para
/// compartir (Tanda 5, task 5.1).
///
/// Pure-render por contrato (per `design.md` § "Plan de archivos"):
/// recibe los valores formateados desde el page y se limita a pintar la
/// composición. NO consulta `DolarApiService` ni el estado del page.
///
/// Branding: usa `Theme.of(context).colorScheme.*` y el asset existente
/// `assets/resources/appIcon.png` — sin colores hardcodeados ni hex (per
/// memory `project_wallex_ai_chat_v2`).
///
/// El card se monta SIEMPRE en el árbol bajo `Offstage(offstage: true)` con
/// `RepaintBoundary` + `GlobalKey` (per design § "Render del share card off-
/// screen") para que la captura sea instantánea cuando el usuario pulsa
/// share.
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.fromCurrency,
    required this.toCurrency,
    required this.fromAmountText,
    required this.toAmountText,
    required this.sourceLabel,
    required this.timestampLabel,
    required this.equalsSeparator,
    required this.footerText,
  });

  /// Currency origen (la pane activa en el page).
  final Currency fromCurrency;

  /// Currency destino (la pane convertida).
  final Currency toCurrency;

  /// Monto origen ya formateado (ej. `25,00`). Se renderiza junto con el
  /// símbolo de `fromCurrency`.
  final String fromAmountText;

  /// Monto destino ya formateado (ej. `12.118,50`). Se renderiza junto con el
  /// símbolo de `toCurrency`.
  final String toAmountText;

  /// Label de la fuente de tasa, ya resuelto por el page (ej. `Paralelo`,
  /// `Paralelo (USDT)`, `Manual`).
  final String sourceLabel;

  /// Timestamp del último fetch ya formateado por el page (ej.
  /// `27/04/2026 14:23` o `—`).
  final String timestampLabel;

  /// Separador entre montos (`=` por default, viene de i18n para que sea
  /// localizable si hace falta).
  final String equalsSeparator;

  /// Footer brandeado (`Generado con Wallex` o equivalente).
  final String footerText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Card de ancho fijo para garantizar consistencia entre devices al
    // capturar el frame. 360 es el ancho mínimo común y entra cómodo en
    // share sheets de WhatsApp/Telegram.
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primaryContainer,
              colors.surfaceContainerHighest,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outlineVariant, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShareCardHeader(
              sourceLabel: sourceLabel,
              timestampLabel: timestampLabel,
            ),
            const SizedBox(height: 18),
            _ShareCardConversion(
              fromCurrency: fromCurrency,
              toCurrency: toCurrency,
              fromAmountText: fromAmountText,
              toAmountText: toAmountText,
              equalsSeparator: equalsSeparator,
              primaryColor: colors.onPrimaryContainer,
              secondaryColor: colors.onSurfaceVariant,
              amountStyle: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onPrimaryContainer,
              ),
              codeStyle: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 18),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: 12),
            _ShareCardFooter(
              footerText: footerText,
              brandColor: colors.primary,
              footerStyle: text.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareCardHeader extends StatelessWidget {
  const _ShareCardHeader({
    required this.sourceLabel,
    required this.timestampLabel,
  });

  final String sourceLabel;
  final String timestampLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sourceLabel,
                style: text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timestampLabel,
                style: text.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.swap_horizontal_circle_outlined,
          size: 22,
          color: colors.primary,
        ),
      ],
    );
  }
}

class _ShareCardConversion extends StatelessWidget {
  const _ShareCardConversion({
    required this.fromCurrency,
    required this.toCurrency,
    required this.fromAmountText,
    required this.toAmountText,
    required this.equalsSeparator,
    required this.primaryColor,
    required this.secondaryColor,
    required this.amountStyle,
    required this.codeStyle,
  });

  final Currency fromCurrency;
  final Currency toCurrency;
  final String fromAmountText;
  final String toAmountText;
  final String equalsSeparator;
  final Color primaryColor;
  final Color secondaryColor;
  final TextStyle? amountStyle;
  final TextStyle? codeStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConversionRow(
          currency: fromCurrency,
          amountText: fromAmountText,
          amountStyle: amountStyle,
          codeStyle: codeStyle,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: Text(
              equalsSeparator,
              style: codeStyle?.copyWith(color: secondaryColor, fontSize: 18),
            ),
          ),
        ),
        _ConversionRow(
          currency: toCurrency,
          amountText: toAmountText,
          amountStyle: amountStyle,
          codeStyle: codeStyle,
        ),
      ],
    );
  }
}

class _ConversionRow extends StatelessWidget {
  const _ConversionRow({
    required this.currency,
    required this.amountText,
    required this.amountStyle,
    required this.codeStyle,
  });

  final Currency currency;
  final String amountText;
  final TextStyle? amountStyle;
  final TextStyle? codeStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: currency.displayFlagIcon(size: 28),
        ),
        const SizedBox(width: 10),
        Text(currency.code, style: codeStyle),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            amountText,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: amountStyle,
          ),
        ),
      ],
    );
  }
}

class _ShareCardFooter extends StatelessWidget {
  const _ShareCardFooter({
    required this.footerText,
    required this.brandColor,
    required this.footerStyle,
  });

  final String footerText;
  final Color brandColor;
  final TextStyle? footerStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Logo brandeado: usamos el asset existente `appIcon.png` (mismo que
        // `DisplayAppIcon`). El frame del share card ya da contraste; no se
        // aplican wrappers ni colores hardcodeados.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/resources/appIcon.png',
            width: 20,
            height: 20,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 8),
        Text(footerText, style: footerStyle),
      ],
    );
  }
}
