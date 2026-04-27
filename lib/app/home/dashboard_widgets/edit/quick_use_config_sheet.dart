import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/services/dashboard_layout_service.dart';
import 'package:wallex/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart';
import 'package:wallex/app/home/dashboard_widgets/widgets/quick_use_widget.dart';
import 'package:wallex/core/presentation/widgets/wallex_reorderable_list.dart';

/// Bottom sheet con dos pestañas para configurar los avatares de un widget
/// `quickUse`:
///   1. **Mostrados** — `WallexReorderableList` con drag-and-drop para
///      reordenar; cada fila incluye avatar circular + label + botón
///      remover (`−`).
///   2. **Ocultos** — `Wrap` de avatares no seleccionados con un badge `+`
///      en la esquina; tap para añadir al final de la lista mostrada.
///
/// La persistencia ocurre vía [DashboardLayoutService.updateConfig] en cada
/// cambio (granularidad fina; el debouncer del service coalesces los
/// writes). Cerrar el sheet (botón "Listo", swipe-down o tap fuera) no
/// requiere acción adicional — los cambios ya viajaron al stream.
///
/// Spec `dashboard-quick-use` § configEditor.
class QuickUseConfigSheet extends StatefulWidget {
  const QuickUseConfigSheet({super.key, required this.descriptor});

  final WidgetDescriptor descriptor;

  @override
  State<QuickUseConfigSheet> createState() => _QuickUseConfigSheetState();
}

class _QuickUseConfigSheetState extends State<QuickUseConfigSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Lista mutable de chips. Se inicializa desde el descriptor y se
  /// persiste en cada cambio.
  late List<QuickActionId> _chips;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _chips = _readChipsFromDescriptor(widget.descriptor);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static List<QuickActionId> _readChipsFromDescriptor(WidgetDescriptor d) {
    final raw = d.config['chips'];
    if (raw is! List) return List<QuickActionId>.from(kQuickUseDefaultChips);
    final out = <QuickActionId>[];
    for (final entry in raw) {
      if (entry is! String) continue;
      final id = QuickActionId.tryParse(entry);
      if (id == null) continue;
      out.add(id);
    }
    if (out.isEmpty) {
      return List<QuickActionId>.from(kQuickUseDefaultChips);
    }
    return out;
  }

  void _persist() {
    DashboardLayoutService.instance.updateConfig(
      widget.descriptor.instanceId,
      <String, dynamic>{
        ...widget.descriptor.config,
        'chips': _chips.map((id) => id.name).toList(growable: false),
      },
    );
  }

  void _addChip(QuickActionId id) {
    if (_chips.contains(id)) return;
    setState(() => _chips.add(id));
    _persist();
  }

  void _removeChip(QuickActionId id) {
    if (!_chips.contains(id)) return;
    setState(() => _chips.remove(id));
    _persist();
  }

  void _reorderChip(int from, int to) {
    setState(() {
      // ReorderableListView entrega `to` ya post-removal cuando to>from. La
      // semántica de [DashboardLayoutService.reorder] coincide: ahí también
      // ajustamos el índice. Aquí mantenemos la misma convención local.
      final moved = _chips.removeAt(from);
      final insertAt = to > from ? to - 1 : to;
      _chips.insert(insertAt, moved);
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Configurar atajos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Listo'),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Mostrados'),
              Tab(text: 'Ocultos'),
            ],
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildShownTab(context),
                _buildHiddenTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────── Mostrados (drag-to-reorder + remover) ───────────────

  Widget _buildShownTab(BuildContext context) {
    final theme = Theme.of(context);
    if (_chips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Añade atajos desde la pestaña "Ocultos".',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return WallexReorderableList(
      totalItemCount: _chips.length,
      onReorder: _reorderChip,
      spaceBetween: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemBuilder: (context, index, isOrdering) {
        final id = _chips[index];
        return _ShownRow(
          key: ValueKey('shown-${id.name}'),
          id: id,
          isOrdering: isOrdering,
          onRemove: () => _removeChip(id),
        );
      },
    );
  }

  // ─────────────── Ocultos (catálogo agrupado por categoría) ───────────────

  Widget _buildHiddenTab(BuildContext context) {
    // Construimos los hidden por categoría conservando el orden de
    // declaración del enum. Mantener categorías ayuda a escanear el
    // catálogo aunque el visual sea ya un wrap de avatares.
    final hiddenByCategory = <QuickActionCategory, List<QuickActionId>>{
      QuickActionCategory.toggle: <QuickActionId>[],
      QuickActionCategory.navigation: <QuickActionId>[],
      QuickActionCategory.quickTx: <QuickActionId>[],
    };
    for (final id in QuickActionId.values) {
      if (_chips.contains(id)) continue;
      final action = QuickActionDispatcher.get(id);
      if (action == null) continue;
      hiddenByCategory[action.category]!.add(id);
    }

    final empty = hiddenByCategory.values.every((l) => l.isEmpty);
    if (empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Todos los atajos disponibles ya están en uso.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        _buildHiddenSection(
          context,
          'Toggles',
          hiddenByCategory[QuickActionCategory.toggle]!,
        ),
        _buildHiddenSection(
          context,
          'Atajos',
          hiddenByCategory[QuickActionCategory.navigation]!,
        ),
        _buildHiddenSection(
          context,
          'Acciones rápidas',
          hiddenByCategory[QuickActionCategory.quickTx]!,
        ),
      ],
    );
  }

  Widget _buildHiddenSection(
    BuildContext context,
    String title,
    List<QuickActionId> ids,
  ) {
    if (ids.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 12,
            children: <Widget>[
              for (final id in ids)
                SizedBox(
                  width: kQuickUseSlotWidth,
                  child: _HiddenAvatar(
                    id: id,
                    onAdd: () => _addChip(id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila de "Mostrados" — avatar circular + label + drag handle + botón
/// remover. El gesto de drag real viene del [WallexReorderableList] padre
/// (`ReorderableDelayedDragStartListener`); el icono es solo afordancia
/// visual.
class _ShownRow extends StatelessWidget {
  const _ShownRow({
    super.key,
    required this.id,
    required this.isOrdering,
    required this.onRemove,
  });

  final QuickActionId id;
  final bool isOrdering;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final action = QuickActionDispatcher.get(id);

    return Material(
      color: isOrdering
          ? cs.primary.withValues(alpha: 0.08)
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: <Widget>[
            // Avatar circular grande — misma escala que la vista Rial.
            _AvatarCircle(
              icon: action?.icon ?? Icons.bolt_rounded,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                action?.label(context) ?? id.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.remove_circle_outline_rounded),
              color: cs.error,
              onPressed: onRemove,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Icon(
                Icons.drag_indicator_rounded,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar de "Ocultos" con badge `+` superpuesto. Tap añade el id al final
/// de la lista mostrada.
class _HiddenAvatar extends StatelessWidget {
  const _HiddenAvatar({required this.id, required this.onAdd});

  final QuickActionId id;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final action = QuickActionDispatcher.get(id);
    if (action == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: kQuickUseAvatarSize,
          height: kQuickUseAvatarSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: _AvatarCircle(
                  icon: action.icon,
                  onTap: onAdd,
                ),
              ),
              // Badge `+` flotante (top-right). El stack se permite con
              // `Clip.none` para no recortarlo al borde del avatar.
              Positioned(
                top: -2,
                right: -2,
                child: IgnorePointer(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 2),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: 12,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          action.label(context),
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

/// Avatar circular reutilizado por filas y wraps del sheet. Mantiene la
/// misma escala visual que [QuickUseAvatar] del widget de vista. No se
/// reusa [QuickUseAvatar] directamente porque aquí no queremos label
/// inline y sí queremos un onTap opcional sin label.
class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
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
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper para abrir el sheet desde otros sitios de la app.
Future<void> showQuickUseConfigSheet(
  BuildContext context, {
  required WidgetDescriptor descriptor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) => QuickUseConfigSheet(descriptor: descriptor),
  );
}
