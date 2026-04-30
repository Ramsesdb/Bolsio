import 'package:flutter/material.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/services/dashboard_layout_service.dart';
import 'package:bolsio/core/database/services/exchange-rate/exchange_rate_service.dart';

/// Bottom sheet para configurar las divisas mostradas en un widget
/// `exchangeRateCard`. Dos secciones en una columna scrollable (no `TabBar`,
/// a diferencia de [QuickUseConfigSheet] — el catálogo es plano y pequeño):
///
///   1. **Mostradas** — chips con botón remover (`×`).
///   2. **Agregar divisa** — divisas con tasas activas en la base de datos
///      (filtradas vía `ExchangeRateService.getExchangeRates()` para no
///      mostrar las ~170 divisas seed que no tendrían fila visible al
///      agregarse), excluyendo las ya mostradas. Tap para añadir.
///
/// La persistencia ocurre vía [DashboardLayoutService.updateConfig] en cada
/// add/remove (granularidad fina; el debouncer del service coalesces los
/// writes al disco). Cerrar el sheet (botón "Listo", swipe-down o tap fuera)
/// no requiere acción adicional — los cambios ya viajaron al stream.
///
/// Spec `dashboard-widgets/exchange-rate-card` § REQ-4, REQ-5, REQ-6.
class ExchangeRateConfigSheet extends StatefulWidget {
  const ExchangeRateConfigSheet({super.key, required this.descriptor});

  final WidgetDescriptor descriptor;

  @override
  State<ExchangeRateConfigSheet> createState() =>
      _ExchangeRateConfigSheetState();
}

class _ExchangeRateConfigSheetState extends State<ExchangeRateConfigSheet> {
  /// Lista mutable de divisas mostradas. Se inicializa desde el descriptor
  /// y se persiste en cada cambio.
  late List<String> _shown;

  @override
  void initState() {
    super.initState();
    _shown = _readCurrenciesFromDescriptor(widget.descriptor);
  }

  static List<String> _readCurrenciesFromDescriptor(WidgetDescriptor d) {
    final raw = d.config['currencies'];
    if (raw is! List) return <String>['VES', 'EUR'];
    final out = raw.whereType<String>().map((s) => s.toUpperCase()).toList();
    return out.isEmpty ? <String>['VES', 'EUR'] : out;
  }

  void _persist() {
    // Lee el descriptor VIVO desde el service (mismo patrón que
    // [QuickUseConfigSheet._persist]) en lugar de usar el snapshot capturado
    // en `widget.descriptor` (initState). Si entre la apertura del sheet y
    // este `_persist` ocurre un `pullAllData()` (sync Firebase) o cualquier
    // otra mutación al layout, hacer merge contra el snapshot viejo
    // sobrescribiría los cambios concurrentes y, en el siguiente ciclo de
    // sync, las divisas agregadas desaparecerían.
    final service = DashboardLayoutService.instance;
    final live = service.current.widgets.firstWhere(
      (w) => w.instanceId == widget.descriptor.instanceId,
      orElse: () => widget.descriptor,
    );
    service.updateConfig(
      widget.descriptor.instanceId,
      <String, dynamic>{
        ...live.config,
        'currencies': List<String>.unmodifiable(_shown),
      },
    );
  }

  void _addCurrency(String code) {
    if (_shown.contains(code)) return;
    setState(() => _shown.add(code));
    _persist();
  }

  void _removeCurrency(String code) {
    if (!_shown.contains(code)) return;
    setState(() => _shown.remove(code));
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
          // Drag handle.
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Header row con título + botón "Listo".
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Configurar divisas',
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
          // Contenido scrollable. Constraint para que el sheet no rebase la
          // pantalla en teléfonos cortos.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              shrinkWrap: true,
              children: [
                _buildShownSection(context),
                const SizedBox(height: 16),
                _buildAddSection(context),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────── Mostradas (chips con remover) ───────────────

  Widget _buildShownSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mostradas',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        if (_shown.isEmpty)
          Text(
            'No hay divisas seleccionadas.',
            style: theme.textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in _shown)
                Chip(
                  label: Text(code),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  onDeleted: () => _removeCurrency(code),
                ),
            ],
          ),
      ],
    );
  }

  // ─────────────── Agregar divisa (catálogo backed por DB) ───────────────

  Widget _buildAddSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agregar divisa',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder(
          stream: ExchangeRateService.instance.getExchangeRates(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            // Conjunto de divisas con al menos una fila viva en la DB,
            // menos las que ya están mostradas. ADR-4 / REQ-5: filtramos
            // por filas reales para garantizar que toda divisa agregable
            // produzca una fila visible en el widget.
            final available = snap.data!
                .map((r) => r.currencyCode.toUpperCase())
                .toSet()
              ..removeAll(_shown);

            if (available.isEmpty) {
              return Text(
                'Todas las divisas disponibles ya están en uso.',
                style: theme.textTheme.bodySmall,
              );
            }

            final sorted = available.toList()..sort();
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in sorted)
                  ActionChip(
                    label: Text(code),
                    avatar: const Icon(Icons.add_rounded, size: 16),
                    onPressed: () => _addCurrency(code),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Helper para abrir el sheet desde otros sitios de la app (paridad con
/// [showQuickUseConfigSheet]).
Future<void> showExchangeRateConfigSheet(
  BuildContext context, {
  required WidgetDescriptor descriptor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) => ExchangeRateConfigSheet(descriptor: descriptor),
  );
}
