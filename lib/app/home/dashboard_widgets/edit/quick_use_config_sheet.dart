import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/services/dashboard_layout_service.dart';
import 'package:wallex/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart';
import 'package:wallex/app/home/dashboard_widgets/widgets/quick_use_widget.dart';
import 'package:wallex/core/presentation/widgets/wallex_reorderable_list.dart';

/// Bottom sheet con dos pestañas para configurar los chips de un widget
/// `quickUse`:
///   1. **Atajos** — catálogo agrupado por categoría con un check para
///      añadir/quitar.
///   2. **Orden** — `WallexReorderableList` con los chips actualmente
///      seleccionados, drag handle para reordenar.
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

  void _toggleChip(QuickActionId id) {
    setState(() {
      if (_chips.contains(id)) {
        _chips.remove(id);
      } else {
        _chips.add(id);
      }
    });
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
              Tab(text: 'Atajos'),
              Tab(text: 'Orden'),
            ],
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCatalogTab(context),
                _buildOrderTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogTab(BuildContext context) {
    // Agrupa por [QuickActionCategory] preservando orden de declaración del
    // enum dentro de cada grupo.
    final byCategory = <QuickActionCategory, List<QuickActionId>>{
      QuickActionCategory.toggle: <QuickActionId>[],
      QuickActionCategory.navigation: <QuickActionId>[],
      QuickActionCategory.quickTx: <QuickActionId>[],
    };
    for (final id in QuickActionId.values) {
      final action = QuickActionDispatcher.get(id);
      if (action == null) continue;
      byCategory[action.category]!.add(id);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildCategorySection(
          context,
          'Toggles',
          byCategory[QuickActionCategory.toggle]!,
        ),
        _buildCategorySection(
          context,
          'Atajos',
          byCategory[QuickActionCategory.navigation]!,
        ),
        _buildCategorySection(
          context,
          'Acciones rápidas',
          byCategory[QuickActionCategory.quickTx]!,
        ),
      ],
    );
  }

  Widget _buildCategorySection(
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        ...ids.map((id) {
          final action = QuickActionDispatcher.get(id);
          final selected = _chips.contains(id);
          return CheckboxListTile(
            value: selected,
            onChanged: (_) => _toggleChip(id),
            secondary: Icon(action?.icon ?? Icons.bolt_rounded),
            title: Text(action?.label(context) ?? id.name),
            controlAffinity: ListTileControlAffinity.trailing,
          );
        }),
      ],
    );
  }

  Widget _buildOrderTab(BuildContext context) {
    if (_chips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Selecciona al menos un atajo en la pestaña anterior.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return WallexReorderableList(
      totalItemCount: _chips.length,
      onReorder: _reorderChip,
      spaceBetween: 4,
      itemBuilder: (context, index, isOrdering) {
        final id = _chips[index];
        final action = QuickActionDispatcher.get(id);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Material(
            color: isOrdering
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                : Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(action?.icon ?? Icons.bolt_rounded),
              title: Text(action?.label(context) ?? id.name),
              trailing: const Icon(Icons.drag_indicator),
            ),
          ),
        );
      },
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
