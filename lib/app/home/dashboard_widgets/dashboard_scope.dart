import 'package:flutter/widgets.dart';
import 'package:nitido/core/models/date-utils/date_period_state.dart';

/// Scope contextual que el `DashboardPage` provee a sus widgets dinámicos
/// durante el render iterativo (Wave 2.2).
///
/// Cada `DashboardWidgetSpec.builder` recibe un `BuildContext` cuya tree
/// incluye este `InheritedWidget` — los widgets que necesiten compartir
/// estado del header (período seleccionado, fuente de tasas activa,
/// refresh tick, lista de cuentas visibles tras Hidden Mode) lo leen vía
/// `DashboardScope.of(context)`.
///
/// Razones para introducir este scope (en lugar de pasar todo por
/// parámetro o leerlo de servicios globales):
///
/// 1. **Período seleccionado** — `DatePeriodState` vive en el `State` del
///    dashboard (el usuario lo cambia con el chip del header). No hay
///    servicio global, así que el InheritedWidget es la única forma de
///    propagarlo a hijos sin reescribir todos los specs.
/// 2. **Refresh tick** — el `RefreshIndicator` incrementa un contador para
///    forzar `didUpdateWidget` en streams downstream (espejo del patrón ya
///    usado por `TotalBalanceSummaryWidget`).
/// 3. **Visible account ids** — el dashboard ya hace UNA suscripción
///    upstream a `HiddenModeService.visibleAccountIdsStream` para evitar
///    el coste de N suscripciones. Compartirla por scope mantiene la
///    optimización de Wave 1A.
/// 4. **Rate source** — el spec `dashboard-widgets` permite a múltiples
///    widgets reaccionar al chip BCV/Paralelo. Aquí se expone el valor
///    actual y un callback para mutarlo (el padre persiste en
///    `SettingKey.preferredRateSource` y rebobinea sus streams).
///
/// El scope se mantiene MÍNIMO — todo dato que YA viva en un servicio
/// con `shareValue()` (Account, Transaction, ExchangeRate, etc.) NO se
/// duplica aquí: los widgets se suscriben directamente al servicio.
class DashboardScope extends InheritedWidget {
  const DashboardScope({
    super.key,
    required this.dateRangeService,
    required this.rateSource,
    required this.onRateSourceChanged,
    required this.refreshTick,
    required this.visibleAccountIds,
    required super.child,
  });

  /// Periodo activo seleccionado en el chip del header.
  final DatePeriodState dateRangeService;

  /// Fuente de tasas activa (`'bcv'` | `'paralelo'`). Mantenida en el
  /// `_DashboardPageState` para que `IncomeOrExpenseCard` y
  /// `TotalBalanceSummaryWidget` reaccionen al mismo valor sin pasar por
  /// `appStateSettings` (lookup síncrono que no rebobinea streams).
  final String rateSource;

  /// Callback invocado cuando un widget interno (ej. el chip dentro de
  /// `TotalBalanceSummaryWidget`) cambia la fuente. El padre persiste en
  /// `SettingKey.preferredRateSource` y propaga vía `setState`.
  final ValueChanged<String> onRateSourceChanged;

  /// Contador incrementado en pull-to-refresh. Los widgets que cachean
  /// streams en `initState` lo leen en `didUpdateWidget` para reasignar
  /// suscripciones — patrón equivalente al `_refreshTick` que ya usa
  /// `TotalBalanceSummaryWidget`.
  final int refreshTick;

  /// Lista de IDs de cuenta visibles tras aplicar Hidden Mode. Pasada por
  /// el dashboard desde su `StreamBuilder` upstream sobre
  /// `HiddenModeService.visibleAccountIdsStream`.
  ///
  /// `null` significa "el stream aún no emitió" — los widgets DEBEN
  /// degradar a un comportamiento sensible (ej. ocultar filtro o esperar)
  /// pero NO crashear.
  final List<String>? visibleAccountIds;

  /// Lookup helper. Lanza si no hay `DashboardScope` ancestral — uso
  /// dentro de los builders del registry, que SIEMPRE corren bajo el
  /// scope del dashboard.
  static DashboardScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DashboardScope>();
    assert(
      scope != null,
      'DashboardScope.of() invoked without a DashboardScope ancestor. '
      'Wrap the widget tree with a DashboardScope (see DashboardPage.build).',
    );
    return scope!;
  }

  /// Variante opcional para builders que pueden funcionar fuera del
  /// dashboard (ej. previews / tests sin scope montado).
  static DashboardScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DashboardScope>();
  }

  @override
  bool updateShouldNotify(DashboardScope oldWidget) {
    return rateSource != oldWidget.rateSource ||
        refreshTick != oldWidget.refreshTick ||
        dateRangeService.startDate != oldWidget.dateRangeService.startDate ||
        dateRangeService.endDate != oldWidget.dateRangeService.endDate ||
        !_listEquals(visibleAccountIds, oldWidget.visibleAccountIds);
  }

  static bool _listEquals(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
