import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kilatex/core/database/app_db.dart';
import 'package:kilatex/core/presentation/helpers/snackbar.dart';
import 'package:kilatex/core/services/statement_import/statement_batches_service.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';

/// Banner sticky que aparece encima de la lista de transacciones de la cuenta
/// cuando existe al menos un batch de statement_import reciente (≤ 7 días)
/// y ofrece la acción "Deshacer".
///
/// V1 muestra solamente el batch más reciente. Ampliaciones (multi-batch,
/// bottom sheet con histórico) quedan para iteraciones futuras.
class StatementImportUndoBanner extends StatelessWidget {
  const StatementImportUndoBanner({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StatementImportBatchInDB>>(
      stream: StatementBatchesService.instance.watchRecentBatches(accountId),
      builder: (context, snapshot) {
        final batches = snapshot.data ?? const <StatementImportBatchInDB>[];
        if (batches.isEmpty) return const SizedBox.shrink();
        final latest = batches.first;
        return _Banner(batch: latest);
      },
    );
  }
}

class _Banner extends StatefulWidget {
  const _Banner({required this.batch});

  final StatementImportBatchInDB batch;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  bool _working = false;

  int get _txCount {
    final ids =
        StatementBatchesService.instance.decodeTransactionIds(widget.batch);
    return ids.length;
  }

  Future<void> _confirmUndo() async {
    if (_working) return;
    final count = _txCount;
    final t = Translations.of(context);
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.statement_import.undo.dialog_title),
        content: Text(t.statement_import.undo.dialog_body(n: count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.statement_import.undo.dialog_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.statement_import.undo.dialog_confirm),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    setState(() => _working = true);
    try {
      await StatementBatchesService.instance.undo(widget.batch.id);
      if (!mounted) return;
      WallexSnackbar.success(
        SnackbarParams(Translations.of(context).statement_import.undo.success),
      );
    } catch (e) {
      if (!mounted) return;
      WallexSnackbar.error(
        SnackbarParams.fromError(e),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _relative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inHours < 1) return 'hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return 'hace ${diff.inDays} días';
    return DateFormat('dd/MM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final count = _txCount;
    final relative = _relative(widget.batch.createdAt);
    final modes = _decodeModes(widget.batch.mode);
    final modeTag = modes.contains('informative')
        ? ' · ${t.statement_import.modes.informative}'
        : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.file_download_done_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${t.statement_import.undo.banner_title} · ${t.statement_import.undo.banner_body(n: count, date: relative)}',
                  style: tt.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$relative$modeTag',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _working ? null : _confirmUndo,
            icon: _working
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.undo_rounded, size: 18),
            label: Text(t.statement_import.undo.undo_cta),
          ),
        ],
      ),
    );
  }

  List<String> _decodeModes(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {}
    return const <String>[];
  }
}
