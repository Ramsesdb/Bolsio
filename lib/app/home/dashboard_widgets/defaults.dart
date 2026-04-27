import 'package:wallex/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';

/// Defaults para el layout del dashboard.
///
/// Implementa el contrato del spec `dashboard-layout` § Defaults por
/// `onboardingGoals` y § Fallback. La lógica vive aquí (separada del
/// `DashboardLayoutService`) para que el onboarding (`_applyChoices`) y el
/// renderer (`dashboard.page.dart::initState`) puedan invocar exactamente
/// la misma función sin importar el servicio entero.
///
/// Notas de diseño:
///   - `WidgetType.quickUse` SIEMPRE va en posición 0 (precondición del
///     spec). Aunque el goal mapping ya lo prepende por convención, lo
///     forzamos al final para no depender del orden del mapping.
///   - El cap a 8 widgets aplica DESPUÉS de la deduplicación por type. Si
///     `quickUse` no entra dentro de los primeros 8 elementos del set
///     ordenado por goals, igualmente se incluye al inicio (no consume
///     slot extra — el cap se aplica al resultado final post-prepend).
///   - El `instanceId` se genera con uuid v4 vía `WidgetDescriptor.create`,
///     que reusa `generateUUID()` (`package:uuid` ya está en pubspec.yaml).
///   - El `defaultConfig` de cada `WidgetType` se resuelve consultando el
///     `DashboardWidgetRegistry` — así un cambio en el spec del widget se
///     propaga a los defaults sin tocar este archivo.
class DashboardLayoutDefaults {
  const DashboardLayoutDefaults._();

  /// Mapping declarativo `goal → WidgetType[]` del spec dashboard-layout
  /// § Defaults por onboardingGoals. El orden importa: dentro de un goal,
  /// los widgets aparecen en este orden; entre goals, gana el orden de
  /// inserción del set del usuario.
  static const Map<String, List<WidgetType>> _goalToWidgets =
      <String, List<WidgetType>>{
        'track_expenses': <WidgetType>[
          WidgetType.quickUse,
          WidgetType.totalBalanceSummary,
          WidgetType.recentTransactions,
          WidgetType.incomeExpensePeriod,
        ],
        'save_usd': <WidgetType>[
          WidgetType.quickUse,
          WidgetType.totalBalanceSummary,
          WidgetType.exchangeRateCard,
          WidgetType.accountCarousel,
        ],
        'reduce_debt': <WidgetType>[
          WidgetType.quickUse,
          WidgetType.totalBalanceSummary,
          WidgetType.accountCarousel,
          WidgetType.recentTransactions,
        ],
        'budget': <WidgetType>[
          WidgetType.quickUse,
          WidgetType.totalBalanceSummary,
          WidgetType.incomeExpensePeriod,
          WidgetType.recentTransactions,
        ],
        'analyze': <WidgetType>[
          WidgetType.quickUse,
          WidgetType.incomeExpensePeriod,
          WidgetType.recentTransactions,
          WidgetType.exchangeRateCard,
        ],
      };

  /// Cap declarado en el spec § Defaults — se aplica POST-dedupe pero
  /// PRE-prepend de `quickUse`. `quickUse` cuenta hacia el cap (decisión
  /// registrada en `tasks.md` § Decisiones tomadas).
  static const int _maxWidgets = 8;

  /// Construye un layout default a partir del set de goals seleccionado en
  /// el onboarding.
  ///
  /// Algoritmo:
  ///   1. Recorrer los goals en su orden de iteración (caller decide
  ///      `LinkedHashSet` o similar).
  ///   2. Por cada goal, recorrer sus widgets recomendados en orden.
  ///   3. Deduplicar por `WidgetType`: la PRIMERA aparición gana —los
  ///      duplicados subsiguientes se ignoran.
  ///   4. Garantizar `quickUse` en posición 0 (forzado al inicio si el
  ///      mapping ya lo incluyó; añadido si no — caso `goals = {}`).
  ///   5. Capar a [_maxWidgets].
  ///   6. Materializar `WidgetDescriptor` por cada type vía el registry
  ///      (defaultConfig + defaultSize). Si el registry no tiene el spec
  ///      registrado (no debería pasar — `registerDashboardWidgets()` corre
  ///      antes de `runApp`), ese type se omite.
  ///
  /// Cuando [goals] está vacío el resultado equivale al de [fallback].
  static DashboardLayout fromGoals(Set<String> goals) {
    if (goals.isEmpty) return fallback();

    final ordered = <WidgetType>[];
    final seen = <WidgetType>{};
    for (final goal in goals) {
      final list = _goalToWidgets[goal];
      if (list == null) continue;
      for (final type in list) {
        if (seen.add(type)) ordered.add(type);
      }
    }

    // Garantiza quickUse en posición 0 — el mapping ya lo incluye, pero si
    // el set de goals está vacío de mappings conocidos lo añadimos a mano.
    final withQuickUse = _ensureQuickUseFirst(ordered);

    // Cap a 8.
    final capped = withQuickUse.length > _maxWidgets
        ? withQuickUse.sublist(0, _maxWidgets)
        : withQuickUse;

    return DashboardLayout(
      schemaVersion: DashboardLayout.currentSchemaVersion,
      widgets: List<WidgetDescriptor>.unmodifiable(
        _buildDescriptors(capped),
      ),
    );
  }

  /// Layout neutro y útil para usuarios cuyo `dashboardLayout` está vacío
  /// pero ya completaron onboarding (e.g. relogin sin blob Firebase). Spec
  /// `dashboard-layout` § Fallback.
  ///
  /// Lista deliberadamente más rica que el caso `goals={}` puro: sirve
  /// como punto de partida razonable que el usuario puede customizar luego
  /// desde edit mode.
  static DashboardLayout fallback() {
    final types = <WidgetType>[
      WidgetType.quickUse,
      WidgetType.totalBalanceSummary,
      WidgetType.accountCarousel,
      WidgetType.incomeExpensePeriod,
      WidgetType.recentTransactions,
      WidgetType.exchangeRateCard,
      WidgetType.pendingImportsAlert,
    ];

    return DashboardLayout(
      schemaVersion: DashboardLayout.currentSchemaVersion,
      widgets: List<WidgetDescriptor>.unmodifiable(_buildDescriptors(types)),
    );
  }

  // ─────────── Helpers privados ───────────

  static List<WidgetType> _ensureQuickUseFirst(List<WidgetType> input) {
    if (input.isEmpty) return <WidgetType>[WidgetType.quickUse];
    if (input.first == WidgetType.quickUse) return input;
    final out = <WidgetType>[WidgetType.quickUse];
    for (final t in input) {
      if (t != WidgetType.quickUse) out.add(t);
    }
    return out;
  }

  static List<WidgetDescriptor> _buildDescriptors(List<WidgetType> types) {
    final registry = DashboardWidgetRegistry.instance;
    final out = <WidgetDescriptor>[];
    for (final type in types) {
      final spec = registry.get(type);
      if (spec == null) {
        // El registry no tiene el spec — silenciosamente omitido. Los tests
        // (Phase 3) cubren que TODOS los WidgetType.values estén
        // registrados, así que esta rama solo se activaría tras un
        // refactor que olvide actualizar el bootstrap.
        continue;
      }
      out.add(
        WidgetDescriptor.create(
          type: type,
          size: spec.defaultSize,
          config: spec.defaultConfig,
        ),
      );
    }
    return out;
  }
}
