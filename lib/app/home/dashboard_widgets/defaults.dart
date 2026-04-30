import 'package:bolsio/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/registry.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';

/// Defaults para el layout del dashboard.
///
/// SIMPLIFICADO: por ahora, independientemente de lo que el usuario elija
/// en el onboarding, siempre se muestran los mismos 4 widgets fijos:
///   1. Ajustes rápidos (quickUse) — solo nuevo ingreso, nuevo egreso,
///      calculadora.
///   2. Mis cuentas (accountCarousel).
///   3. Tasas de cambio (exchangeRateCard).
///   4. Movimientos por revisar (pendingImportsAlert).
///
/// El mapping por goals está comentado para reactivación futura.
class DashboardLayoutDefaults {
  const DashboardLayoutDefaults._();

  // ── COMENTADO: mapping goal → widgets (reactivar en el futuro) ────────
  //
  // /// Mapping declarativo `goal → WidgetType[]` del spec dashboard-layout
  // /// § Defaults por onboardingGoals. El orden importa: dentro de un goal,
  // /// los widgets aparecen en este orden; entre goals, gana el orden de
  // /// inserción del set del usuario.
  // static const Map<String, List<WidgetType>> _goalToWidgets =
  //     <String, List<WidgetType>>{
  //       'track_expenses': <WidgetType>[
  //         WidgetType.quickUse,
  //         WidgetType.totalBalanceSummary,
  //         WidgetType.recentTransactions,
  //         WidgetType.incomeExpensePeriod,
  //       ],
  //       'save_usd': <WidgetType>[
  //         WidgetType.quickUse,
  //         WidgetType.totalBalanceSummary,
  //         WidgetType.exchangeRateCard,
  //         WidgetType.accountCarousel,
  //       ],
  //       'reduce_debt': <WidgetType>[
  //         WidgetType.quickUse,
  //         WidgetType.totalBalanceSummary,
  //         WidgetType.accountCarousel,
  //         WidgetType.recentTransactions,
  //       ],
  //       'budget': <WidgetType>[
  //         WidgetType.quickUse,
  //         WidgetType.totalBalanceSummary,
  //         WidgetType.incomeExpensePeriod,
  //         WidgetType.recentTransactions,
  //       ],
  //       'analyze': <WidgetType>[
  //         WidgetType.quickUse,
  //         WidgetType.incomeExpensePeriod,
  //         WidgetType.recentTransactions,
  //         WidgetType.exchangeRateCard,
  //       ],
  //     };

  // /// Cap declarado en el spec § Defaults — se aplica POST-dedupe pero
  // /// PRE-prepend de `quickUse`. `quickUse` cuenta hacia el cap (decisión
  // /// registrada en `tasks.md` § Decisiones tomadas).
  // static const int _maxWidgets = 8;

  /// Los 4 widgets fijos que se muestran siempre en el dashboard,
  /// independientemente de los goals del onboarding.
  static const List<WidgetType> _fixedWidgets = <WidgetType>[
    WidgetType.quickUse,
    WidgetType.accountCarousel,
    WidgetType.exchangeRateCard,
    WidgetType.pendingImportsAlert,
  ];

  /// Config especial para el widget quickUse: solo muestra nuevo ingreso,
  /// nuevo egreso y calculadora.
  static Map<String, dynamic> get _quickUseFixedConfig =>
      <String, dynamic>{
        'chips': <String>[
          QuickActionId.newIncomeTransaction.name,
          QuickActionId.newExpenseTransaction.name,
          QuickActionId.goToCalculator.name,
        ],
      };

  /// Config para el widget exchangeRateCard que respeta la moneda preferida
  /// del usuario:
  ///   - pref = USD → mostrar VES + EUR (la pareja volátil para usuarios USD)
  ///   - pref = VES → mostrar USD + EUR (la pareja de referencia para usuarios VES)
  ///   - otro / null → mostrar USD + EUR (default seguro para contexto venezolano)
  static Map<String, dynamic> get _exchangeRateCardConfig {
    final pref = appStateSettings[SettingKey.preferredCurrency];
    final currencies = (pref == 'USD')
        ? <String>['VES', 'EUR']
        : <String>['USD', 'EUR'];
    return <String, dynamic>{'currencies': currencies};
  }

  /// Construye un layout default a partir del set de goals seleccionado en
  /// el onboarding.
  ///
  /// SIMPLIFICADO: ignora [goals] y siempre devuelve los 4 widgets fijos.
  /// El parámetro se mantiene para no romper la firma del caller
  /// (`onboarding.dart::_applyChoices`).
  // ignore: avoid-unused-parameters
  static DashboardLayout fromGoals(Set<String> goals) {
    // ── COMENTADO: lógica original basada en goals ──────────────────────
    //
    // if (goals.isEmpty) return fallback();
    //
    // final ordered = <WidgetType>[];
    // final seen = <WidgetType>{};
    // for (final goal in goals) {
    //   final list = _goalToWidgets[goal];
    //   if (list == null) continue;
    //   for (final type in list) {
    //     if (seen.add(type)) ordered.add(type);
    //   }
    // }
    //
    // final withQuickUse = _ensureQuickUseFirst(ordered);
    // final withCore = _ensureAccountCarouselSecond(withQuickUse);
    //
    // final capped = withCore.length > _maxWidgets
    //     ? withCore.sublist(0, _maxWidgets)
    //     : withCore;
    //
    // return DashboardLayout(
    //   schemaVersion: DashboardLayout.currentSchemaVersion,
    //   widgets: List<WidgetDescriptor>.unmodifiable(
    //     _buildDescriptors(capped),
    //   ),
    // );

    return _buildFixedLayout();
  }

  /// Layout neutro y útil para usuarios cuyo `dashboardLayout` está vacío
  /// pero ya completaron onboarding (e.g. relogin sin blob Firebase). Spec
  /// `dashboard-layout` § Fallback.
  ///
  /// SIMPLIFICADO: devuelve los mismos 4 widgets fijos que [fromGoals].
  static DashboardLayout fallback() {
    // ── COMENTADO: layout fallback original más rico ────────────────────
    //
    // final types = <WidgetType>[
    //   WidgetType.quickUse,
    //   WidgetType.totalBalanceSummary,
    //   WidgetType.accountCarousel,
    //   WidgetType.incomeExpensePeriod,
    //   WidgetType.recentTransactions,
    //   WidgetType.exchangeRateCard,
    //   WidgetType.pendingImportsAlert,
    // ];
    //
    // return DashboardLayout(
    //   schemaVersion: DashboardLayout.currentSchemaVersion,
    //   widgets: List<WidgetDescriptor>.unmodifiable(
    //     _buildDescriptors(types),
    //   ),
    // );

    return _buildFixedLayout();
  }

  // ─────────── Helpers privados ───────────

  /// Construye el layout fijo con los 4 widgets y el config especial de
  /// quickUse (solo nuevo ingreso, nuevo egreso, calculadora).
  static DashboardLayout _buildFixedLayout() {
    return DashboardLayout(
      schemaVersion: DashboardLayout.currentSchemaVersion,
      widgets: List<WidgetDescriptor>.unmodifiable(
        _buildDescriptors(_fixedWidgets),
      ),
    );
  }

  // ── COMENTADO: helpers de reordenamiento (ya no necesarios) ───────────
  //
  // static List<WidgetType> _ensureQuickUseFirst(
  //   List<WidgetType> input,
  // ) {
  //   if (input.isEmpty) return <WidgetType>[WidgetType.quickUse];
  //   if (input.first == WidgetType.quickUse) return input;
  //   final out = <WidgetType>[WidgetType.quickUse];
  //   for (final t in input) {
  //     if (t != WidgetType.quickUse) out.add(t);
  //   }
  //   return out;
  // }
  //
  // static List<WidgetType> _ensureAccountCarouselSecond(
  //   List<WidgetType> input,
  // ) {
  //   final out = <WidgetType>[];
  //   var inserted = false;
  //   for (var i = 0; i < input.length; i++) {
  //     final t = input[i];
  //     out.add(t);
  //     if (i == 0 && t == WidgetType.quickUse) {
  //       out.add(WidgetType.accountCarousel);
  //       inserted = true;
  //     }
  //   }
  //   if (!inserted) {
  //     if (!out.contains(WidgetType.accountCarousel)) {
  //       out.add(WidgetType.accountCarousel);
  //     }
  //     return out;
  //   }
  //   final deduped = <WidgetType>[];
  //   var seenAccountCarousel = false;
  //   for (final t in out) {
  //     if (t == WidgetType.accountCarousel) {
  //       if (seenAccountCarousel) continue;
  //       seenAccountCarousel = true;
  //     }
  //     deduped.add(t);
  //   }
  //   return deduped;
  // }

  /// Construye los descriptores a partir de una lista de tipos.
  /// Para `quickUse`, aplica el config fijo con solo 3 chips.
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

      // Para quickUse, usar el config fijo con solo 3 acciones en vez del
      // default completo del registry.
      // Para exchangeRateCard, usar el config pref-aware (REQ-2) que respeta
      // la moneda preferida del usuario.
      final config = switch (type) {
        WidgetType.quickUse => _quickUseFixedConfig,
        WidgetType.exchangeRateCard => _exchangeRateCardConfig,
        _ => spec.defaultConfig,
      };

      out.add(
        WidgetDescriptor.create(
          type: type,
          size: spec.defaultSize,
          config: config,
        ),
      );
    }
    return out;
  }
}
