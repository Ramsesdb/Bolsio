import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/dashboard_scope.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';
import 'package:wallex/app/home/widgets/horizontal_scrollable_account_list.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Wrapper público de [HorizontalScrollableAccountList] para que el
/// dashboard dinámico pueda renderizarlo desde un `WidgetDescriptor`.
///
/// Wave 1B sólo registra el spec — la composición actual del dashboard
/// sigue invocando [HorizontalScrollableAccountList] inline. Wave 2 cambia
/// el body a `StreamBuilder<DashboardLayout>` y delega aquí.
///
/// El filtro de `accountIds` (config) actúa como capa adicional sobre el
/// stream de visibilidad ya compartido (`HiddenModeService
/// .visibleAccountIdsStream`): si está presente, el widget intersecta esa
/// lista con la pasada por config; si está ausente o vacía, se respeta el
/// comportamiento actual (todas las cuentas visibles).
class AccountCarouselWidget extends StatelessWidget {
  const AccountCarouselWidget({
    super.key,
    required this.dateRangeService,
    required this.visibleAccountIds,
    this.configAccountIds,
  });

  /// Periodo activo del dashboard (forwardeado a la lista para calcular
  /// variación por cuenta).
  final DatePeriodState dateRangeService;

  /// Lista de IDs visibles tras Hidden Mode — el dashboard ya hace una
  /// suscripción única a `HiddenModeService.visibleAccountIdsStream` y la
  /// propaga a sus hijos. Pasar `null` significa "stream sin emitir aún"
  /// (la lista interna decide qué mostrar).
  final List<String>? visibleAccountIds;

  /// Subset opcional declarado en `WidgetDescriptor.config['accountIds']`.
  /// `null` = todas las cuentas visibles.
  final List<String>? configAccountIds;

  /// Calcula el subconjunto efectivo respetando ambos filtros.
  List<String>? get _effectiveVisibleIds {
    final visible = visibleAccountIds;
    if (visible == null) return null;
    final filter = configAccountIds;
    if (filter == null || filter.isEmpty) return visible;
    return visible.where(filter.contains).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return HorizontalScrollableAccountList(
      dateRangeService: dateRangeService,
      visibleAccountIds: _effectiveVisibleIds,
    );
  }
}

/// Registra el spec del widget `accountCarousel`. Invocado desde
/// `registry_bootstrap.dart::registerDashboardWidgets`.
void registerAccountCarouselWidget() {
  DashboardWidgetRegistry.instance.register(
    DashboardWidgetSpec(
      type: WidgetType.accountCarousel,
      displayName: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.account_carousel.name,
      description: (ctx) => Translations.of(
        ctx,
      ).home.dashboard_widgets.account_carousel.description,
      icon: Icons.credit_card_rounded,
      defaultSize: WidgetSize.fullWidth,
      allowedSizes: const <WidgetSize>{WidgetSize.fullWidth},
      defaultConfig: const <String, dynamic>{
        'accountIds': null,
        'showHidden': false,
      },
      recommendedFor: const <String>{'save_usd', 'reduce_debt'},
      builder: (context, descriptor, {required editing}) {
        // Wave 2 — render real. Lee `dateRangeService` / `visibleAccountIds`
        // del [DashboardScope] y filtra opcionalmente con la lista de
        // `accountIds` declarada en `descriptor.config` (config-time
        // filter, intersectado con Hidden Mode).
        final scope = DashboardScope.of(context);
        final rawIds = descriptor.config['accountIds'];
        final configIds = rawIds is List
            ? rawIds.whereType<String>().toList(growable: false)
            : null;
        return KeyedSubtree(
          key: ValueKey('${descriptor.type.name}-${descriptor.instanceId}'),
          child: AccountCarouselWidget(
            dateRangeService: scope.dateRangeService,
            visibleAccountIds: scope.visibleAccountIds,
            configAccountIds: configIds,
          ),
        );
      },
    ),
  );
}
