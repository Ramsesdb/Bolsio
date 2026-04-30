import 'package:flutter/material.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/registry.dart';
import 'package:bolsio/core/presentation/responsive/breakpoints.dart';
import 'package:bolsio/core/utils/logger.dart';

/// Renderer responsivo del cuerpo del dashboard.
///
/// Itera sobre `layout.widgets` y mapea cada `WidgetDescriptor` al builder
/// del [DashboardWidgetRegistry]. Layout regla:
///   - `WidgetSize.fullWidth` → ocupa todo el ancho disponible.
///   - `WidgetSize.medium` → 50% en breakpoints `>= md`, fullWidth en
///     viewports más estrechos. La heurística viene del spec
///     `dashboard-widgets` (no se introduce un grid librería externa, el
///     `Wrap` de Flutter es suficiente para 8 widgets).
///   - Cada hijo va envuelto en `KeyedSubtree(key: ValueKey(instanceId))`
///     para preservar el `State` interno entre reorders (spec
///     `dashboard-widgets` § Estabilidad por instanceId).
///
/// Cuando un descriptor referencia un `WidgetType` no registrado, el widget
/// se omite y se loguea un warning (spec `dashboard-widgets` § Build con
/// type ausente).
///
/// Vive en su propio archivo (en lugar de dentro de `dashboard.page.dart`)
/// para que el suite de tests pueda importarlo sin arrastrar las
/// dependencias pesadas del `DashboardPage` (FAB, AccountService, etc.).
class DashboardLayoutBody extends StatelessWidget {
  const DashboardLayoutBody({super.key, required this.layout});

  final DashboardLayout layout;

  @override
  Widget build(BuildContext context) {
    if (layout.widgets.isEmpty) {
      // Empty layout: durante onboarding o tras un fallback aún no
      // resuelto. Renderizar nada — el header arriba ya da contexto.
      return const SizedBox.shrink();
    }

    final registry = DashboardWidgetRegistry.instance;
    final breakpoint = BreakPoint.of(context);
    final isWide = breakpoint.isLargerOrEqualTo(BreakpointID.md);

    final slots = <DashboardLayoutSlot>[];
    for (final descriptor in layout.widgets) {
      final spec = registry.get(descriptor.type);
      if (spec == null) {
        Logger.printDebug(
          '[DashboardPage] Skipping descriptor ${descriptor.instanceId}: '
          'type ${descriptor.type.name} is not registered.',
        );
        continue;
      }
      // Spec auto-hide: si el predicado `shouldRender` existe y devuelve
      // `false`, no construimos el widget — evita tarjetas fantasma en
      // view mode. En edit mode este predicado se ignora (ver
      // `_DashboardEditBody` en `dashboard.page.dart`).
      final shouldRender = spec.shouldRender?.call(descriptor) ?? true;
      if (!shouldRender) continue;

      final built = spec.builder(context, descriptor, editing: false);
      final useHalfWidth =
          isWide && descriptor.size == WidgetSize.medium;
      slots.add(
        DashboardLayoutSlot(
          instanceId: descriptor.instanceId,
          halfWidth: useHalfWidth,
          child: built,
        ),
      );
    }

    if (slots.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // `Wrap` resuelve el caso fullWidth + medium adyacentes sin
          // depender de un grid externo. Cada slot declara su ancho
          // intrínseco (50% / 100%) vía un `SizedBox(width)` envolvente.
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: slots
                .map(
                  (slot) => SizedBox(
                    width: slot.halfWidth
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth,
                    child: slot,
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

/// Wraps a built widget in a stable [ValueKey] derived from the descriptor's
/// `instanceId` so reorders preserve subtree state.
class DashboardLayoutSlot extends StatelessWidget {
  const DashboardLayoutSlot({
    super.key,
    required this.instanceId,
    required this.halfWidth,
    required this.child,
  });

  final String instanceId;
  final bool halfWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey<String>('layout-slot-$instanceId'),
      child: child,
    );
  }
}
