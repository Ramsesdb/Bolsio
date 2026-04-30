import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/registry.dart';
import 'package:bolsio/app/home/dashboard_widgets/services/dashboard_layout_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';

/// Bottom sheet con catálogo completo de widgets disponibles. Cada item
/// del catálogo se puede tocar para añadir una nueva instancia al layout.
///
/// Spec `dashboard-edit-mode` § Bottom sheet "Agregar widget".
///
/// Comportamiento:
///   - Lista TODOS los specs del registry (no oculta los ya presentes —
///     el spec MVP permite múltiples instancias del mismo type, ej. dos
///     `incomeExpensePeriod` con distinto periodo).
///   - Marca con un badge "Recomendado" los specs cuyo `recommendedFor`
///     interseca con `appStateSettings[SettingKey.onboardingGoals]`.
///   - Tap en un item:
///       - Crea un nuevo `WidgetDescriptor` con `instanceId` v4 fresco,
///         `defaultSize` y `defaultConfig` del spec.
///       - Llama `DashboardLayoutService.add(descriptor)`.
///       - Cierra el sheet.
class AddWidgetSheet extends StatelessWidget {
  const AddWidgetSheet({super.key});

  /// Lee `onboardingGoals` desde `appStateSettings`. Tolera JSON inválido
  /// (devuelve set vacío).
  static Set<String> _readOnboardingGoals() {
    final raw = appStateSettings[SettingKey.onboardingGoals];
    if (raw == null || raw.isEmpty) return const <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } on FormatException {
      // Silencioso — set vacío equivale a "ningún recomendado".
    }
    return const <String>{};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goals = _readOnboardingGoals();
    final specs = DashboardWidgetRegistry.instance.recommendedFor(goals);

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
                  'Agregar widget',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              itemCount: specs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final spec = specs[index];
                final recommended = spec.recommendedFor.any(goals.contains);
                return _AddWidgetTile(
                  spec: spec,
                  recommended: recommended,
                  onTap: () {
                    final descriptor = WidgetDescriptor.create(
                      type: spec.type,
                      size: spec.defaultSize,
                      config: spec.defaultConfig,
                    );
                    DashboardLayoutService.instance.add(descriptor);
                    Navigator.of(context).maybePop();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddWidgetTile extends StatelessWidget {
  const _AddWidgetTile({
    required this.spec,
    required this.recommended,
    required this.onTap,
  });

  final DashboardWidgetSpec spec;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primary.withValues(alpha: 0.12),
                radius: 22,
                child: Icon(spec.icon, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            spec.displayName(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          _RecommendedBadge(),
                        ],
                      ],
                    ),
                    if (spec.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        spec.description!(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.add_rounded,
                color: cs.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'Recomendado',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      ),
    );
  }
}

/// Helper para abrir el sheet desde el dashboard.
Future<void> showAddWidgetSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) => const AddWidgetSheet(),
  );
}
