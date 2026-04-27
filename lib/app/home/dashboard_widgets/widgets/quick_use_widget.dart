import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';
import 'package:wallex/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart';
import 'package:wallex/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/private_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/presentation/responsive/breakpoints.dart';
import 'package:wallex/core/presentation/widgets/tappable.dart';
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

/// Widget público que renderiza una grilla de chips circulares para las
/// quick actions seleccionadas por el usuario.
///
/// Lee `descriptor.config['chips']` (lista de strings con
/// `QuickActionId.name`); si está vacío usa [kQuickUseDefaultChips]. Cada
/// chip resuelve su [QuickAction] via [QuickActionDispatcher] y al pulsarlo
/// invoca el callback registrado.
///
/// Es reactivo a [PrivateModeService.privateModeStream] y al stream de
/// `isLockedStream` para que los chips de toggle muestren el estado actual
/// (label dinámico). El stream de `preferredCurrency` no tiene un service
/// reactivo dedicado en wallex; el chip `togglePreferredCurrency` se
/// reconstruye con el `appStateSettings` global cuando el descriptor
/// recibe nuevos chips o cuando el padre re-emite (después de un toggle el
/// dispatcher hace `setItem(updateGlobalState: true)` y el host del
/// dashboard rebuildea por el stream del layout).
class QuickUseWidget extends StatelessWidget {
  const QuickUseWidget({
    super.key,
    required this.descriptor,
  });

  final WidgetDescriptor descriptor;

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
    final theme = Theme.of(context);
    final isWide = BreakPoint.of(context).isLargerOrEqualTo(BreakpointID.md);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            runSpacing: 14,
            spacing: 14,
            children: chips
                .map(
                  (id) => SizedBox(
                    width: isWide ? 92 : 64,
                    child: _QuickUseChip(id: id),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

/// Botón circular con ícono + label. Se suscribe a los streams reactivos
/// solo cuando el chip pertenece al subconjunto que cambia con ellos
/// (`togglePrivateMode` → privateModeStream; `toggleHiddenMode` →
/// isLockedStream). Para los demás chips el `StreamBuilder` se omite y la
/// reconstrucción es trivial.
class _QuickUseChip extends StatelessWidget {
  const _QuickUseChip({required this.id});

  final QuickActionId id;

  @override
  Widget build(BuildContext context) {
    final action = QuickActionDispatcher.get(id);
    if (action == null) return const SizedBox.shrink();

    switch (id) {
      case QuickActionId.togglePrivateMode:
        return StreamBuilder<bool>(
          stream: PrivateModeService.instance.privateModeStream,
          initialData: appStateSettings[SettingKey.privateMode] == '1',
          builder: (context, snapshot) {
            final on = snapshot.data ?? false;
            return _ChipButton(
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
            return _ChipButton(
              icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              label: action.label(context),
              highlighted: locked,
              onTap: () => action.action(context),
            );
          },
        );
      default:
        return _ChipButton(
          icon: action.icon,
          label: action.label(context),
          onTap: () => action.action(context),
        );
    }
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = highlighted ? cs.primary : cs.onSurface;
    return Tappable(
      onTap: onTap,
      bgColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: base.withValues(alpha: 0.12),
              radius: 22,
              child: Icon(icon, size: 22, color: base),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: base.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Registra el spec del widget `quickUse`.
///
/// El `defaultConfig.chips` codifica los defaults como
/// `List<String>` (los `name`s del enum) — ese es el shape persistente que
/// viaja en el JSON del layout. La conversión a [QuickActionId] vive en
/// `QuickUseWidget._activeChips`.
void registerQuickUseWidget() {
  DashboardWidgetRegistry.instance.register(
    DashboardWidgetSpec(
      type: WidgetType.quickUse,
      displayName: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.quick_use.name,
      description: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.quick_use.description,
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
          key: ValueKey('${descriptor.type.name}-${descriptor.instanceId}'),
          child: QuickUseWidget(descriptor: descriptor),
        );
      },
      configEditor: (context, descriptor) {
        // Indirección al builder mutable [quickUseConfigEditorBuilder].
        // Mantiene `widgets/quick_use_widget.dart` desacoplado del sheet
        // concreto (vive en `edit/`).
        final builder = quickUseConfigEditorBuilder;
        if (builder == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Editor no inicializado. Revisa registry_bootstrap.dart.',
              ),
            ),
          );
        }
        return builder(context, descriptor);
      },
    ),
  );
}
