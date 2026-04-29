import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';
import 'package:wallex/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart';
import 'package:wallex/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/private_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Builder mutable usado por el spec del `quickUse` para abrir su
/// configEditor sin obligar al archivo del widget a importar el sheet
/// (que vive en `edit/quick_use_config_sheet.dart`). El bootstrap conecta
/// el builder real tras registrar el spec — ver
/// `registry_bootstrap.dart::registerDashboardWidgets`.
///
/// Mientras esté en `null`, el spec devuelve un placeholder informativo
/// para que el patrón sea seguro de invocar incluso si el wiring no se
/// completó (raro — solo afectaría tests que olviden bootstrap).
Widget Function(BuildContext, WidgetDescriptor)? quickUseConfigEditorBuilder;

/// Defaults aplicados cuando `descriptor.config['chips']` está ausente o
/// vacío. Coherentes con el spec `dashboard-quick-use` § Defaults: el
/// usuario que aún no configuró sus atajos ve un set práctico que cubre
/// las acciones más usadas.
const List<QuickActionId> kQuickUseDefaultChips = <QuickActionId>[
  QuickActionId.togglePrivateMode,
  QuickActionId.newExpenseTransaction,
  QuickActionId.newIncomeTransaction,
  QuickActionId.goToSettings,
  QuickActionId.openTransactions,
  QuickActionId.openExchangeRates,
  QuickActionId.goToBudgets,
  QuickActionId.goToReports,
];

/// Tamaño visual de los avatares de quick action. Constantes compartidas
/// con `edit/quick_use_config_sheet.dart` para mantener la coherencia
/// entre la vista y el editor.
const double kQuickUseAvatarSize = 56;
const double kQuickUseAvatarIconSize = 26;
const double kQuickUseSlotWidth = 72;

/// Widget público que renderiza una fila de tiles rectangulares premium
/// para las quick actions seleccionadas por el usuario.
///
/// Lee `descriptor.config['chips']` (lista de strings con
/// `QuickActionId.name`); si está vacío usa [kQuickUseDefaultChips]. Cada
/// tile resuelve su [QuickAction] via [QuickActionDispatcher] y al
/// pulsarlo invoca el callback registrado.
///
/// Es reactivo a [PrivateModeService.privateModeStream] y al stream de
/// `isLockedStream` para que los tiles de toggle muestren el estado
/// actual (label dinámico).
class QuickUseWidget extends StatelessWidget {
  const QuickUseWidget({
    super.key,
    required this.descriptor,
    this.editing = false,
  });

  final WidgetDescriptor descriptor;

  /// `true` cuando el dashboard está en modo edición.
  final bool editing;

  /// Resuelve la lista de [QuickActionId] activos a partir del config del
  /// descriptor. Filtra ids desconocidos (downgrade-safe) y, si el resultado
  /// queda vacío, cae a [kQuickUseDefaultChips].
  List<QuickActionId> get _activeChips {
    final raw = descriptor.config['chips'];
    if (raw is! List) return kQuickUseDefaultChips;
    final out = <QuickActionId>[];
    for (final entry in raw) {
      if (entry is! String) continue;
      final id = QuickActionId.tryParse(entry);
      if (id == null) continue;
      out.add(id);
    }
    if (out.isEmpty) return kQuickUseDefaultChips;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final chips = _activeChips;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _QuickUseTile(id: chips[i])),
          ],
        ],
      ),
    );
  }
}

/// Tile reactivo: se suscribe a streams solo cuando el chip pertenece al
/// subconjunto que cambia con ellos (`togglePrivateMode` →
/// privateModeStream; `toggleHiddenMode` → isLockedStream). Para los
/// demás tiles el `StreamBuilder` se omite y la reconstrucción es trivial.
class _QuickUseTile extends StatelessWidget {
  const _QuickUseTile({required this.id});

  final QuickActionId id;

  @override
  Widget build(BuildContext context) {
    final action = QuickActionDispatcher.get(id);
    if (action == null) return const SizedBox.shrink();

    switch (id) {
      case QuickActionId.togglePrivateMode:
        return StreamBuilder<bool>(
          stream: PrivateModeService.instance.privateModeStream,
          initialData:
              appStateSettings[SettingKey.privateMode] == '1',
          builder: (context, snapshot) {
            final on = snapshot.data ?? false;
            return _QuickActionCard(
              icon: on
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              label: action.label(context),
              highlighted: on,
              onTap: () => action.action(context),
            );
          },
        );
      case QuickActionId.toggleHiddenMode:
        return StreamBuilder<bool>(
          stream: HiddenModeService.instance.isLockedStream,
          initialData: HiddenModeService.instance.isLocked,
          builder: (context, snapshot) {
            final locked = snapshot.data ?? true;
            return _QuickActionCard(
              icon: locked
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
              label: action.label(context),
              highlighted: locked,
              onTap: () => action.action(context),
            );
          },
        );
      default:
        return _QuickActionCard(
          icon: action.icon,
          label: action.label(context),
          onTap: () => action.action(context),
        );
    }
  }
}

/// Tile rectangular premium con icono + label. Estilo Wallex: fondo
/// con tinte del primary, borde sutil, esquinas redondeadas 14px.
///
/// Cuando [highlighted] es `true` (toggle activo), usa el primary lleno
/// para destacar el estado activo.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final Color bg;
    final Color fg;
    final Color borderColor;

    if (highlighted) {
      bg = cs.primary;
      fg = cs.onPrimary;
      borderColor = cs.primary.withValues(alpha: 0.3);
    } else if (isDark) {
      bg = cs.primary.withValues(alpha: 0.08);
      fg = cs.onSurface.withValues(alpha: 0.9);
      borderColor = cs.primary.withValues(alpha: 0.12);
    } else {
      bg = cs.primaryContainer.withValues(alpha: 0.5);
      fg = cs.onPrimaryContainer;
      borderColor = cs.primary.withValues(alpha: 0.08);
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 24, color: fg),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
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

/// Avatar circular grande con label debajo. Reutilizado por el config
/// sheet para mantener la consistencia visual entre vista y editor.
///
/// - Tamaño: [kQuickUseAvatarSize] (56) con icono
///   [kQuickUseAvatarIconSize].
/// - Colores: tinte derivado de `primaryContainer` por defecto;
///   `primary` lleno cuando [highlighted] es `true` (toggle activo).
/// - Label: 1 línea, ellipsis, centrado, ancho fijo del slot.
class QuickUseAvatar extends StatelessWidget {
  const QuickUseAvatar({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final Color bg;
    final Color fg;
    if (highlighted) {
      bg = cs.primary;
      fg = cs.onPrimary;
    } else {
      bg = cs.primaryContainer;
      fg = cs.onPrimaryContainer;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: bg,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: kQuickUseAvatarSize,
              height: kQuickUseAvatarSize,
              child: Center(
                child: Icon(
                  icon,
                  size: kQuickUseAvatarIconSize,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Registra el spec del widget `quickUse`.
///
/// El `defaultConfig.chips` codifica los defaults como
/// `List<String>` (los `name`s del enum) — ese es el shape persistente
/// que viaja en el JSON del layout. La conversión a [QuickActionId] vive
/// en `QuickUseWidget._activeChips`.
void registerQuickUseWidget() {
  DashboardWidgetRegistry.instance.register(
    DashboardWidgetSpec(
      type: WidgetType.quickUse,
      displayName: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.quick_use.name,
      description: (ctx) => Translations.of(
        ctx,
      ).home.dashboard_widgets.quick_use.description,
      icon: Icons.bolt_rounded,
      defaultSize: WidgetSize.fullWidth,
      allowedSizes: const <WidgetSize>{WidgetSize.fullWidth},
      defaultConfig: <String, dynamic>{
        'chips': kQuickUseDefaultChips
            .map((id) => id.name)
            .toList(growable: false),
      },
      recommendedFor: const <String>{
        'track_expenses',
        'save_usd',
        'reduce_debt',
        'budget',
        'analyze',
      },
      builder: (context, descriptor, {required editing}) {
        return KeyedSubtree(
          key: ValueKey(
            '${descriptor.type.name}-${descriptor.instanceId}',
          ),
          child: QuickUseWidget(
            descriptor: descriptor,
            editing: editing,
          ),
        );
      },
      configEditor: (context, descriptor) {
        final builder = quickUseConfigEditorBuilder;
        if (builder == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Editor no inicializado. '
                'Revisa registry_bootstrap.dart.',
              ),
            ),
          );
        }
        return builder(context, descriptor);
      },
    ),
  );
}
