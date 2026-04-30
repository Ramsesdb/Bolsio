import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bolsio/core/services/auto_import/capture/capture_event_log.dart';
import 'package:bolsio/core/services/auto_import/capture/capture_health_monitor.dart';
import 'package:bolsio/core/services/auto_import/capture/models/capture_event.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

/// Diagnostic screen that surfaces the ring buffer of capture events so the
/// user can see exactly what happens to every SMS / notification that reaches
/// the orchestrator.
class CaptureDiagnosticsPage extends StatefulWidget {
  const CaptureDiagnosticsPage({super.key});

  @override
  State<CaptureDiagnosticsPage> createState() => _CaptureDiagnosticsPageState();
}

class _CaptureDiagnosticsPageState extends State<CaptureDiagnosticsPage> {
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _ensureHydrated();
  }

  Future<void> _ensureHydrated() async {
    await CaptureEventLog.instance.hydrate();
    if (mounted) setState(() => _hydrated = true);
  }

  bool get _isSpanish {
    final locale = LocaleSettings.currentLocale;
    return locale == AppLocale.es;
  }

  String _tr({required String es, required String en}) =>
      _isSpanish ? es : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(
          es: 'Diagnóstico de capturas',
          en: 'Capture diagnostics',
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: _tr(
              es: 'Copiar diagnóstico',
              en: 'Copy diagnostic',
            ),
            onPressed: _copyDiagnostic,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: _tr(es: 'Limpiar log', en: 'Clear log'),
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: !_hydrated
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<List<CaptureEvent>>(
              valueListenable: CaptureEventLog.instance.listenable,
              builder: (context, events, _) {
                final counters = CaptureEventLog.instance.counters24h();
                // Newest first for display.
                final reversed = events.reversed.toList();
                return Column(
                  children: [
                    _HealthCard(isSpanish: _isSpanish),
                    _DiagnosticsHeader(
                      counters: counters,
                      isSpanish: _isSpanish,
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: reversed.isEmpty
                          ? _EmptyState(isSpanish: _isSpanish)
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: reversed.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final e = reversed[idx];
                                return _CaptureEventTile(
                                  event: e,
                                  isSpanish: _isSpanish,
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
      backgroundColor: theme.colorScheme.surface,
    );
  }

  Future<void> _confirmClear() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_tr(
            es: '¿Limpiar log de capturas?',
            en: 'Clear capture log?',
          )),
          content: Text(_tr(
            es: 'Esta acción elimina los eventos almacenados localmente. '
                'No afecta transacciones ni propuestas ya guardadas.',
            en: 'This removes locally stored diagnostic events. It does not '
                'affect saved transactions or proposals.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_tr(es: 'Cancelar', en: 'Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(_tr(es: 'Limpiar', en: 'Clear')),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await CaptureEventLog.instance.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(
              es: 'Log limpiado',
              en: 'Log cleared',
            )),
          ),
        );
      }
    }
  }

  Future<void> _copyDiagnostic() async {
    final payload = CaptureEventLog.instance.exportJson(limit: 50);
    await Clipboard.setData(ClipboardData(text: payload));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            es: 'Diagnóstico copiado al portapapeles',
            en: 'Diagnostic copied to clipboard',
          )),
        ),
      );
    }
  }
}

class _DiagnosticsHeader extends StatelessWidget {
  final CaptureEventCounters counters;
  final bool isSpanish;

  const _DiagnosticsHeader({
    required this.counters,
    required this.isSpanish,
  });

  String _tr({required String es, required String en}) => isSpanish ? es : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr(
              es: 'Actividad últimas 24 h',
              en: 'Activity last 24 h',
            ),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _StatusChip(
                icon: Icons.inbox_outlined,
                color: theme.colorScheme.primary,
                label: _tr(es: 'Recibidas', en: 'Received'),
                value: counters.received,
              ),
              _StatusChip(
                icon: Icons.check_circle_outline,
                color: Colors.green,
                label: _tr(es: 'Parseadas', en: 'Parsed'),
                value: counters.parsedSuccess,
              ),
              _StatusChip(
                icon: Icons.error_outline,
                color: theme.colorScheme.error,
                label: _tr(es: 'Fallaron', en: 'Failed'),
                value: counters.parsedFailed,
              ),
              _StatusChip(
                icon: Icons.content_copy_outlined,
                color: Colors.grey,
                label: _tr(es: 'Duplicadas', en: 'Duplicate'),
                value: counters.duplicate,
              ),
              _StatusChip(
                icon: Icons.filter_alt_outlined,
                color: Colors.amber.shade800,
                label: _tr(es: 'Filtradas', en: 'Filtered'),
                value: counters.filteredOut,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;

  const _StatusChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.30)),
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        '$value $label',
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isSpanish;

  const _EmptyState({required this.isSpanish});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              isSpanish
                  ? 'Aún no hay eventos.\nLas capturas aparecerán aquí.'
                  : 'No events yet.\nCaptured messages will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureEventTile extends StatelessWidget {
  final CaptureEvent event;
  final bool isSpanish;

  const _CaptureEventTile({
    required this.event,
    required this.isSpanish,
  });

  String _tr({required String es, required String en}) => isSpanish ? es : en;

  String _labelForSource(CaptureEventSource source) {
    switch (source) {
      case CaptureEventSource.notification:
        return _tr(es: 'Notificación', en: 'Notification');
      case CaptureEventSource.sms:
        return 'SMS';
      case CaptureEventSource.api:
        return 'API';
      case CaptureEventSource.receiptImage:
        return _tr(es: 'Recibo (imagen)', en: 'Receipt (image)');
      case CaptureEventSource.voice:
        return _tr(es: 'Voz', en: 'Voice');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _statusIconAndColor(event.status, theme);

    final sourceLabel = _labelForSource(event.source);
    final from = event.packageName ?? event.sender ?? '-';

    final preview = _buildPreview(event);

    return ExpansionTile(
      leading: Icon(icon, color: color),
      title: Row(
        children: [
          Expanded(
            child: Text(
              event.title?.isNotEmpty == true
                  ? event.title!
                  : '$sourceLabel · $from',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _relativeTime(event.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          Text(
            '$sourceLabel · $from',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(
          theme,
          _tr(es: 'Estado', en: 'Status'),
          _statusLabel(event.status),
          valueColor: color,
        ),
        if (event.reason != null && event.reason!.isNotEmpty)
          _detailRow(theme, _tr(es: 'Motivo', en: 'Reason'), event.reason!),
        if (event.matchedProfile != null)
          _detailRow(
            theme,
            _tr(es: 'Perfil', en: 'Profile'),
            event.matchedProfile!,
          ),
        if (event.parsedAmount != null)
          _detailRow(
            theme,
            _tr(es: 'Monto', en: 'Amount'),
            '${event.parsedAmount!.toStringAsFixed(2)} '
                '${event.parsedCurrency ?? ''}',
          ),
        _detailRow(
          theme,
          _tr(es: 'Fecha', en: 'Date'),
          event.timestamp.toLocal().toString(),
        ),
        const SizedBox(height: 8),
        Text(
          _tr(es: 'Contenido completo', en: 'Full content'),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            event.content.isEmpty ? '—' : event.content,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _detailRow(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  String _buildPreview(CaptureEvent event) {
    if (event.content.isNotEmpty) return event.content;
    if (event.title != null && event.title!.isNotEmpty) return event.title!;
    return '—';
  }

  String _statusLabel(CaptureEventStatus status) {
    switch (status) {
      case CaptureEventStatus.received:
        return _tr(es: 'Recibida', en: 'Received');
      case CaptureEventStatus.parsedSuccess:
        return _tr(es: 'Parseada OK', en: 'Parsed OK');
      case CaptureEventStatus.parsedFailed:
        return _tr(es: 'Falló el parseo', en: 'Parse failed');
      case CaptureEventStatus.filteredOut:
        return _tr(es: 'Filtrada', en: 'Filtered out');
      case CaptureEventStatus.duplicate:
        return _tr(es: 'Duplicada', en: 'Duplicate');
      case CaptureEventStatus.systemEvent:
        return _tr(es: 'Sistema', en: 'System');
    }
  }

  (IconData, Color) _statusIconAndColor(
    CaptureEventStatus status,
    ThemeData theme,
  ) {
    switch (status) {
      case CaptureEventStatus.received:
        return (Icons.inbox_outlined, theme.colorScheme.primary);
      case CaptureEventStatus.parsedSuccess:
        return (Icons.check_circle, Colors.green);
      case CaptureEventStatus.parsedFailed:
        return (Icons.cancel, theme.colorScheme.error);
      case CaptureEventStatus.filteredOut:
        return (Icons.filter_alt_outlined, Colors.amber.shade800);
      case CaptureEventStatus.duplicate:
        return (Icons.content_copy, Colors.grey);
      case CaptureEventStatus.systemEvent:
        return (Icons.info_outline, Colors.blue);
    }
  }

  String _relativeTime(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) {
      return isSpanish ? 'ahora' : 'now';
    }
    if (diff.inMinutes < 60) {
      return isSpanish
          ? 'hace ${diff.inMinutes} min'
          : '${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      return isSpanish ? 'hace ${diff.inHours} h' : '${diff.inHours} h ago';
    }
    if (diff.inDays < 7) {
      return isSpanish ? 'hace ${diff.inDays} d' : '${diff.inDays} d ago';
    }
    return '${ts.year}-${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')}';
  }
}

/// Health card shown on top of the diagnostics screen. Mirrors the banner on
/// the settings page but adds the `lastSuccessAt` timestamp — useful to see
/// whether the pipeline has produced any real proposal in the recent past.
class _HealthCard extends StatelessWidget {
  final bool isSpanish;

  const _HealthCard({required this.isSpanish});

  String _tr({required String es, required String en}) => isSpanish ? es : en;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CaptureHealthStatus>(
      valueListenable: CaptureHealthMonitor.instance.statusNotifier,
      builder: (context, status, _) {
        final theme = Theme.of(context);
        final lastEvent = CaptureHealthMonitor.instance.lastEventAt;
        final lastSuccess = CaptureHealthMonitor.instance.lastSuccessAt;

        final (bg, fg, icon, title) = _palette(status, theme);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _onRepair(context),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: fg, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: fg,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tr(
                              es: 'Último evento: '
                                  '${_fmt(lastEvent)}',
                              en: 'Last event: '
                                  '${_fmt(lastEvent)}',
                            ),
                            style: TextStyle(color: fg, fontSize: 12.5),
                          ),
                          Text(
                            _tr(
                              es: 'Último parseo OK: '
                                  '${_fmt(lastSuccess)}',
                              en: 'Last parsed OK: '
                                  '${_fmt(lastSuccess)}',
                            ),
                            style: TextStyle(color: fg, fontSize: 12.5),
                          ),
                          ValueListenableBuilder<DateTime?>(
                            valueListenable: CaptureHealthMonitor
                                .instance.lastResubscribeAtNotifier,
                            builder: (context, ts, _) {
                              return Text(
                                _tr(
                                  es: 'Última reconexión automática: '
                                      '${_fmt(ts)}',
                                  en: 'Last auto-reconnect: '
                                      '${_fmt(ts)}',
                                ),
                                style: TextStyle(color: fg, fontSize: 12.5),
                              );
                            },
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
      },
    );
  }

  Future<void> _onRepair(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(_tr(
          es: 'Reparando listener...',
          en: 'Repairing listener...',
        )),
        duration: const Duration(seconds: 30),
      ),
    );
    final recovered = await CaptureHealthMonitor.instance.repairNow();
    messenger.hideCurrentSnackBar();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          recovered
              ? _tr(es: 'Listener reparado', en: 'Listener repaired')
              : _tr(
                  es: 'No se pudo recuperar, revisa permisos',
                  en: "Couldn't recover — check permissions",
                ),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  (Color bg, Color fg, IconData icon, String title) _palette(
    CaptureHealthStatus status,
    ThemeData theme,
  ) {
    switch (status) {
      case CaptureHealthStatus.healthy:
        return (
          Colors.green.shade50,
          Colors.green.shade900,
          Icons.check_circle_outline,
          _tr(es: 'Listener activo', en: 'Listener active'),
        );
      case CaptureHealthStatus.stale:
        return (
          Colors.amber.shade50,
          Colors.amber.shade900,
          Icons.warning_amber_outlined,
          _tr(
            es: 'Sin eventos recientes',
            en: 'No recent events',
          ),
        );
      case CaptureHealthStatus.unsubscribed:
        return (
          Colors.red.shade50,
          Colors.red.shade900,
          Icons.link_off,
          _tr(
            es: 'Listener desconectado',
            en: 'Listener disconnected',
          ),
        );
      case CaptureHealthStatus.permissionMissing:
        return (
          Colors.red.shade50,
          Colors.red.shade900,
          Icons.lock_outline,
          _tr(
            es: 'Permiso revocado',
            en: 'Permission missing',
          ),
        );
      case CaptureHealthStatus.unknown:
        return (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
          Icons.hourglass_empty,
          _tr(es: 'Evaluando...', en: 'Evaluating...'),
        );
    }
  }

  String _fmt(DateTime? ts) {
    if (ts == null) return _tr(es: 'nunca', en: 'never');
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return _tr(es: 'ahora', en: 'now');
    if (diff.inMinutes < 60) {
      return _tr(
        es: 'hace ${diff.inMinutes} min',
        en: '${diff.inMinutes} min ago',
      );
    }
    if (diff.inHours < 24) {
      return _tr(
        es: 'hace ${diff.inHours} h',
        en: '${diff.inHours} h ago',
      );
    }
    if (diff.inDays < 7) {
      return _tr(
        es: 'hace ${diff.inDays} d',
        en: '${diff.inDays} d ago',
      );
    }
    return '${ts.year}-${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')}';
  }
}
