import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';

/// Marco visual aplicado a cada widget durante edit mode. Spec
/// `dashboard-edit-mode` § Edit frame.
///
/// Responsabilidades:
///   - Renderiza el [child] (el widget real, ya construido por su spec) o
///     un placeholder informativo cuando [showEmptyPlaceholder] es `true`
///     (caso típico: widgets con auto-hide en view mode que en edit mode
///     hay que mostrar para que el usuario pueda quitarlos). El texto del
///     placeholder se toma de `spec.hiddenPlaceholderMessage` y, si es
///     `null`, se usa un fallback genérico.
///   - Bloquea los gestos internos del child con `IgnorePointer` (los taps
///     en cuentas/transacciones del modo view NO deben navegar mientras
///     `_editing == true`).
///   - Header con el nombre del widget (siempre visible) — el estado
///     "oculto" NO se duplica en el header; se comunica únicamente con el
///     placeholder body para no contaminar el copy.
///   - Coloca un botón "X" en la esquina superior derecha (eliminar)
///     DENTRO de los límites del frame para que el hit-test de Flutter lo
///     incluya. Históricamente vivía en `Positioned(top: -22)` pero quedaba
///     fuera del bounding-box del Stack y nunca recibía taps.
///   - Coloca un drag handle decorativo en la esquina superior izquierda —
///     el `ReorderableDragStartListener` real envuelve todo el frame desde
///     el padre (`dashboard.page.dart`).
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
    this.showEmptyPlaceholder = false,
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

  /// Cuando es `true`, el cuerpo del frame muestra un placeholder gris en
  /// lugar del [child]. Se usa para widgets cuyo `shouldRender` está en
  /// `false` (auto-hidden) — el header sigue visible y el usuario puede
  /// quitarlos con la X.
  final bool showEmptyPlaceholder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasConfigEditor =
        spec.configEditor != null && onConfigure != null;
    final displayName = spec.displayName(context);

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
          // El frame ya no usa `Positioned` con offsets negativos: los
          // chrome buttons viven dentro del bounding-box del Stack para
          // que reciban hit-test correctamente. La cabecera con el
          // nombre del widget reserva un alto fijo (`_headerHeight`) que
          // los botones comparten.
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 36, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FrameHeaderLabel(text: displayName),
                      const SizedBox(height: 8),
                      if (showEmptyPlaceholder)
                        _EmptyPlaceholder(
                          colorScheme: cs,
                          message:
                              spec.hiddenPlaceholderMessage?.call(context) ??
                              'Este widget aparecerá cuando tenga datos',
                        )
                      else
                        Opacity(
                          opacity: 0.85,
                          child: IgnorePointer(
                            ignoring: true,
                            child: child,
                          ),
                        ),
                    ],
                  ),
                ),

                // Esquina superior izquierda: drag handle visual.
                Positioned(
                  top: 4,
                  left: 4,
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
                  top: 4,
                  right: 4,
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

/// Etiqueta del header del frame: muestra el nombre i18n del widget. Vive
/// dentro del padding del frame (no es un `Positioned`) para que el ancho
/// se ajuste solo y no se solape con los chrome buttons.
///
/// Nota: el estado "oculto" (cuando el body se reemplaza por el
/// placeholder) NO se anota aquí — se comunica solo a través del
/// placeholder body para no duplicar la información en el header.
class _FrameHeaderLabel extends StatelessWidget {
  const _FrameHeaderLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      // Margen lateral suficiente para que el texto largo no se acerque a
      // los botones (X mide 44 + 8 de padding del frame).
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onSurface.withValues(alpha: 0.75),
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// Placeholder gris para widgets con `shouldRender == false` que se
/// muestran solo en edit mode. Comunica que el widget existe pero no
/// tiene contenido en este momento.
///
/// Diseño: contenedor atenuado + ícono pequeño `visibility_off_outlined`
/// a la izquierda del [message]. Tono informativo, no de error — usa
/// colores derivados de `onSurface` con alpha bajo para no alarmar.
class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({
    required this.colorScheme,
    required this.message,
  });

  final ColorScheme colorScheme;
  final String message;

  @override
  Widget build(BuildContext context) {
    final mutedFg = colorScheme.onSurface.withValues(alpha: 0.55);
    return Container(
      // `constraints` (no `height` fijo) para que el placeholder crezca
      // si el mensaje envuelve a 2 líneas en pantallas estrechas.
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 16,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: mutedFg,
              ),
            ),
          ),
        ],
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
    // GestureDetector con HitTestBehavior.opaque + 44×44 mínimo (Material
    // touch target). El círculo visible se queda en su tamaño original;
    // sólo el área tappable crece. Se usa GestureDetector en lugar de
    // InkWell para que el `ReorderableDragStartListener` que envuelve el
    // frame no consuma el pointer-down antes que el botón.
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            child: Material(
              color: background,
              shape: const CircleBorder(),
              elevation: 1.5,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(icon, size: 16, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
