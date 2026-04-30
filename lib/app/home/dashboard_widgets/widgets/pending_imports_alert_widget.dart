import 'package:flutter/material.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/registry.dart';
import 'package:bolsio/app/transactions/auto_import/pending_imports.page.dart';
import 'package:bolsio/core/database/services/pending_import/pending_import_service.dart';
import 'package:bolsio/core/models/supported-icon/icon_displayer.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

/// Banner que avisa al usuario sobre transacciones importadas
/// automáticamente que esperan revisión. Cuando el conteo es `0` el widget
/// renderiza `SizedBox.shrink()` (altura cero) — el spec lo exige así para
/// que su presencia en el layout no rompa el grid.
///
/// Se subscribe a [PendingImportService.watchPendingCount] (un único
/// stream upstream); múltiples instancias del widget compartirían
/// suscripción gracias al `shareValue` interno del service.
class PendingImportsAlertWidget extends StatelessWidget {
  const PendingImportsAlertWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: PendingImportService.instance.watchPendingCount(),
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) return const SizedBox.shrink();

        final primary = Theme.of(context).colorScheme.primary;
        final onSurface = Theme.of(context).colorScheme.onSurface;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  primary.withValues(alpha: 0.10),
                  primary.withValues(alpha: 0.03),
                ],
              ),
              border: Border.all(
                color: primary.withValues(alpha: 0.20),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => RouteUtils.pushRoute(const PendingImportsPage()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconDisplayer(
                        icon: Icons.priority_high_rounded,
                        mainColor: Theme.of(context).colorScheme.onPrimary,
                        secondaryColor: primary,
                        displayMode: IconDisplayMode.polygon,
                        size: 18,
                        padding: 9,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$count movimiento${count == 1 ? '' : 's'} por revisar',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: onSurface,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Capturado por voz · toca para confirmar',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w400,
                                color: onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: onSurface.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Registra el spec del widget `pendingImportsAlert`. No tiene
/// `recommendedFor` — el usuario lo añade manualmente desde el catálogo.
void registerPendingImportsAlertWidget() {
  DashboardWidgetRegistry.instance.register(
    DashboardWidgetSpec(
      type: WidgetType.pendingImportsAlert,
      displayName: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.pending_imports_alert.name,
      description: (ctx) => Translations.of(
        ctx,
      ).home.dashboard_widgets.pending_imports_alert.description,
      icon: Icons.priority_high_rounded,
      defaultSize: WidgetSize.fullWidth,
      allowedSizes: const <WidgetSize>{WidgetSize.fullWidth},
      defaultConfig: const <String, dynamic>{},
      recommendedFor: const <String>{},
      // Auto-hide en modo view cuando no hay pendientes. El renderer del
      // dashboard salta el slot completo (sin tarjeta vacía) si este
      // predicado devuelve `false`. En edit mode el predicado se ignora
      // y el frame se muestra con un placeholder específico — para que
      // el usuario pueda quitar el widget sin tener que esperar a que
      // aparezcan pendientes.
      shouldRender: (_) =>
          PendingImportService.instance.currentPendingCount > 0,
      // Copy específico del placeholder en edit mode. Hardcoded en
      // español por consistencia con el resto del cuerpo del widget
      // (líneas 79/89), que también vive sin slang. Si en el futuro se
      // i18n-iza el body, mover esto al mismo bundle.
      hiddenPlaceholderMessage: (_) =>
          'Aparecerá cuando tengas movimientos por revisar',
      builder: (context, descriptor, {required editing}) {
        return KeyedSubtree(
          key: ValueKey('${descriptor.type.name}-${descriptor.instanceId}'),
          child: const PendingImportsAlertWidget(),
        );
      },
    ),
  );
}
