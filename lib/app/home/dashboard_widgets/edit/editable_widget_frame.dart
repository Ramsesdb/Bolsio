import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';

/// Marco visual aplicado a cada widget durante edit mode. Spec
/// `dashboard-edit-mode` § Edit frame.
///
/// Responsabilidades:
///   - Renderiza el [child] (el widget real, ya construido por su spec).
///   - Bloquea los gestos internos del child con `IgnorePointer` (los taps
///     en cuentas/transacciones del modo view NO deben navegar mientras
///     `_editing == true`).
///   - Coloca un botón "X" en la esquina superior derecha (eliminar).
///   - Coloca un drag handle en la esquina superior izquierda — el handle
///     es decorativo aquí; el `ReorderableDragStartListener` real envuelve
///     todo el frame desde el padre (`dashboard.page.dart`).
///   - Pinta un borde punteado tenue + opacidad ligera para comunicar
///     "modo edición".
///   - Si [onConfigure] no es `null` Y el spec tiene `configEditor`,
///     muestra un botón "⚙" entre el handle y la X.
///
/// Wave 4 task 4.4: el frame se anima al entrar (scale 0.98 → 1.0 + fade)
/// usando un `TweenAnimationBuilder`. La animación es suave (250 ms) y no
/// afecta la UX de drag — `ReorderableListView` recibe el frame ya pintado
/// porque el `child` solo cambia su transform.
class EditableWidgetFrame extends StatelessWidget {
  const EditableWidgetFrame({
    super.key,
    required this.descriptor,
    required this.spec,
    required this.child,
    required this.onDelete,
    this.onConfigure,
    this.dragHandleIndex,
  });

  final WidgetDescriptor descriptor;
  final DashboardWidgetSpec spec;
  final Widget child;
  final VoidCallback onDelete;

  /// Solo se muestra el botón "⚙" cuando ambos: este callback no es `null`
  /// y `spec.configEditor` no es `null`.
  final VoidCallback? onConfigure;

  /// Índice del item en la lista (no usado directamente — el padre envuelve
  /// con `ReorderableDragStartListener`). Se conserva por simetría con el
  /// patrón de `WallexReorderableList` por si en el futuro queremos un
  /// handle dedicado.
  final int? dragHandleIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasConfigEditor =
        spec.configEditor != null && onConfigure != null;

    return TweenAnimationBuilder<double>(
      // Animación de entrada cuando el usuario toca el lápiz.
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.98 + (0.02 * t),
            child: child,
          ),
        );
      },
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.35),
            width: 1.2,
          ),
          color: cs.primary.withValues(alpha: 0.04),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 28, 4, 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Contenido real, con gestos internos suprimidos.
              Opacity(
                opacity: 0.85,
                child: IgnorePointer(
                  ignoring: true,
                  child: child,
                ),
              ),

              // Esquina superior izquierda: drag handle visual.
              Positioned(
                top: -22,
                left: 8,
                child: _CornerButton(
                  icon: Icons.drag_indicator_rounded,
                  background: cs.surface,
                  foreground: cs.onSurface.withValues(alpha: 0.6),
                  // Sin onTap: el listener real está en el padre. Queda
                  // como pista visual.
                  onTap: null,
                  tooltip: 'Mantén presionado para reordenar',
                ),
              ),

              // Esquina superior derecha: X (eliminar) + opcional ⚙.
              Positioned(
                top: -22,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasConfigEditor) ...[
                      _CornerButton(
                        icon: Icons.tune_rounded,
                        background: cs.surface,
                        foreground: cs.onSurface.withValues(alpha: 0.7),
                        onTap: onConfigure,
                        tooltip: 'Configurar',
                      ),
                      const SizedBox(width: 6),
                    ],
                    _CornerButton(
                      icon: Icons.close_rounded,
                      background: cs.errorContainer,
                      foreground: cs.onErrorContainer,
                      onTap: onDelete,
                      tooltip: 'Quitar',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        elevation: 1.5,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: foreground),
          ),
        ),
      ),
    );
  }
}
