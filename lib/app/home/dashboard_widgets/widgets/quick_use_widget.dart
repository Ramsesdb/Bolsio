import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:bolsio/app/home/dashboard_widgets/edit/quick_use_config_sheet.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/registry.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart';
import 'package:bolsio/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:bolsio/core/database/services/user-setting/private_mode_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

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
/// estilo "Rial" entre la vista y el editor.
const double kQuickUseAvatarSize = 56;
const double kQuickUseAvatarIconSize = 26;
const double kQuickUseSlotWidth = 72;

/// Widget público que renderiza una fila horizontal scrolleable de avatares
/// circulares grandes para las quick actions seleccionadas por el usuario.
///
/// Lee `descriptor.config['chips']` (lista de strings con
/// `QuickActionId.name`); si está vacío usa [kQuickUseDefaultChips]. Cada
/// avatar resuelve su [QuickAction] via [QuickActionDispatcher] y al
/// pulsarlo invoca el callback registrado.
///
/// En modo view añade al final un slot circular con borde punteado (`+`)
/// que abre el [QuickUseConfigSheet] — mismo flujo que el botón ⚙ del
/// edit-frame, pero accesible sin entrar a edit mode. En edit mode no se
/// pinta el slot extra (el frame ya provee su propio botón ⚙ — duplicarlo
/// confunde).
///
/// Es reactivo a [PrivateModeService.privateModeStream] y al stream de
/// `isLockedStream` para que los avatares de toggle muestren el estado
/// actual (label dinámico).
class QuickUseWidget extends StatelessWidget {
  const QuickUseWidget({
    super.key,
    required this.descriptor,
    this.editing = false,
  });

  final WidgetDescriptor descriptor;

  /// `true` cuando el dashboard está en modo edición. En ese caso el slot
  /// del "+" no se pinta (el edit-frame ya provee un botón de configurar).
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

    final children = <Widget>[
      for (final id in chips)
        SizedBox(
          width: kQuickUseSlotWidth,
          child: _QuickUseChip(id: id),
        ),
      if (!editing)
        SizedBox(
          width: kQuickUseSlotWidth,
          child: _AddMoreSlot(descriptor: descriptor),
        ),
    ];

    // Fila horizontal scrolleable. Sin tarjeta interna ni padding pesado:
    // el widget vive directamente sobre el fondo del dashboard, igual que
    // la pantalla de inicio de "Rial".
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Avatar reactivo: se suscribe a streams solo cuando el chip pertenece al
/// subconjunto que cambia con ellos (`togglePrivateMode` → privateModeStream;
/// `toggleHiddenMode` → isLockedStream). Para los demás avatares el
/// `StreamBuilder` se omite y la reconstrucción es trivial.
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
            return QuickUseAvatar(
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
            return QuickUseAvatar(
              icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              label: action.label(context),
              highlighted: locked,
              onTap: () => action.action(context),
            );
          },
        );
      default:
        return QuickUseAvatar(
          icon: action.icon,
          label: action.label(context),
          onTap: () => action.action(context),
        );
    }
  }
}

/// Avatar circular grande con label debajo. Reutilizado por el config sheet
/// para mantener la consistencia visual entre vista y editor.
///
/// - Tamaño: [kQuickUseAvatarSize] (56) con icono [kQuickUseAvatarIconSize].
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
                child: Icon(icon, size: kQuickUseAvatarIconSize, color: fg),
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

/// Slot de "agregar más" — círculo con borde punteado y un `+` central.
/// Se muestra solo en modo view (no editing) y abre el [QuickUseConfigSheet]
/// — mismo flujo que invocaría el ⚙ del edit-frame, pero accesible sin
/// entrar a edit mode. Inspirado en la home de "Rial".
class _AddMoreSlot extends StatelessWidget {
  const _AddMoreSlot({required this.descriptor});

  final WidgetDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final border = cs.onSurface.withValues(alpha: 0.35);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // El borde punteado se pinta con `dotted_border` (ya en pubspec —
        // ver import_csv.page.dart). Usar `CircularDottedBorderOptions`
        // mantiene el look exacto de Rial sin tener que escribir un
        // CustomPainter ad-hoc.
        DottedBorder(
          options: CircularDottedBorderOptions(
            color: border,
            strokeWidth: 1.4,
            dashPattern: const <double>[4, 4],
            strokeCap: StrokeCap.round,
            padding: EdgeInsets.zero,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showQuickUseConfigSheet(
                context,
                descriptor: descriptor,
              ),
              child: SizedBox(
                width: kQuickUseAvatarSize,
                height: kQuickUseAvatarSize,
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    size: kQuickUseAvatarIconSize,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Más',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.7),
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
          child: QuickUseWidget(descriptor: descriptor, editing: editing),
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
