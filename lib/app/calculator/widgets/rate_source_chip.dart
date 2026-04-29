import 'package:flutter/material.dart';
import 'package:wallex/app/calculator/models/rate_source.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Chip que cicla entre las cuatro `RateSource` (BCV → Paralelo → Promedio →
/// Manual → BCV …) y muestra el timestamp del último fetch como "hace N min".
///
/// Stateless por contrato (per `design.md` § "Plan de archivos"): el page
/// inyecta el source actual + `lastFetched` y recibe el callback en cada tap.
/// El widget se limita a renderizar el label correcto y delegar el tap.
///
/// Tanda 4 (task 4.1, 4.2, 4.3): el label fuerza `Paralelo (USDT)` cuando la
/// pane activa-USD es USDT y el source es uno de los 3 cacheados; el
/// `Semantics.label` incluye source + edad para screen readers.
class RateSourceChip extends StatelessWidget {
  const RateSourceChip({
    super.key,
    required this.source,
    required this.lastFetched,
    required this.onTap,
    required this.forceUsdtLabel,
  });

  /// Source actualmente seleccionada en el page state.
  final RateSource source;

  /// Timestamp del último fetch exitoso a `DolarApiService` (cacheado en el
  /// page). `null` antes del primer fetch o tras hard error sin caché.
  final DateTime? lastFetched;

  /// Disparado cuando el usuario tappea el chip — el page avanza al siguiente
  /// `RateSource` en el ciclo fijo.
  final VoidCallback onTap;

  /// Cuando es `true`, el label se reemplaza por `Paralelo (USDT)` (per spec
  /// scenario "USDT label"). El page lo computa: top-pane USDT activo + source
  /// distinto a `manual`.
  final bool forceUsdtLabel;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = Theme.of(context).colorScheme;

    final label = _resolveLabel(t);
    final ageText = _resolveAgeText(t);
    final a11yLabel = t.calculator.source.a11y_label(
      source: label,
      age: ageText,
    );

    return Semantics(
      button: true,
      label: a11yLabel,
      child: Material(
        color: colors.secondaryContainer,
        shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.swap_horizontal_circle_outlined,
                  size: 18,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 14,
                  color: colors.outlineVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  ageText,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSecondaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _resolveLabel(Translations t) {
    if (forceUsdtLabel && source != RateSource.manual) {
      return t.calculator.source.usdt_label;
    }
    switch (source) {
      case RateSource.bcv:
        return t.calculator.source.bcv;
      case RateSource.paralelo:
        return t.calculator.source.paralelo;
      case RateSource.promedio:
        return t.calculator.source.promedio;
      case RateSource.manual:
        return t.calculator.source.manual;
    }
  }

  String _resolveAgeText(Translations t) {
    final fetched = lastFetched;
    if (fetched == null) return t.calculator.source.updated_unknown;

    final delta = DateTime.now().difference(fetched);
    if (delta.inMinutes < 1) return t.calculator.source.updated_just_now;
    return t.calculator.source.updated_ago(minutes: delta.inMinutes);
  }
}
