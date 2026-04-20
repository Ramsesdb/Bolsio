import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wallex/app/accounts/statement_import/statement_import_flow.dart';
import 'package:wallex/app/accounts/statement_import/widgets/si_header.dart';
import 'package:wallex/core/services/statement_import/matching_engine.dart';
import 'package:wallex/core/services/statement_import/models/extracted_row.dart';
import 'package:wallex/core/services/statement_import/statement_extractor_service.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({super.key});

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanCtrl;
  bool _cancelled = false;
  bool _started = false;
  Object? _error;
  int _foundCount = 0;
  bool _done = false;

  String? _lastImageBase64;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final state = StatementImportFlow.of(context);
    final base64 = state.imageBase64;

    if (base64 == null || state.pivotDate == null) return;

    if (!_started || _lastImageBase64 != base64) {
      _lastImageBase64 = base64;
      _started = true;
      _cancelled = false;
      _error = null;
      _foundCount = 0;
      _done = false;
      _runExtract();
    }
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    super.dispose();
  }

  void _runExtract() {
    final flow = StatementImportFlow.of(context);
    final base64 = flow.imageBase64!;
    final pivot = flow.pivotDate!;

    StatementExtractorService()
        .extractFromImage(imageBase64: base64, pivotDate: pivot)
        .timeout(const Duration(seconds: 30))
        .then((rows) {
          if (!mounted || _cancelled) return;
          setState(() {
            _foundCount = rows.length;
            _done = true;
          });
          _onRowsReady(rows);
        })
        .catchError((e, st) {
          debugPrint('ProcessingPage.extract failed: $e\n$st');
          if (!mounted || _cancelled) return;
          setState(() => _error = e);
        });
  }

  Future<void> _onRowsReady(List<ExtractedRow> rows) async {
    if (!mounted) return;
    final flow = StatementImportFlow.of(context);
    flow.onRowsExtracted(rows);

    try {
      final results = await MatchingEngine().matchRows(
        accountId: flow.account.id,
        rows: rows,
        trackedSince: flow.account.trackedSince,
      );
      if (!mounted || _cancelled) return;
      flow.onMatchingComplete(results);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || _cancelled) return;
      flow.goToReview();
    } catch (e, st) {
      debugPrint('ProcessingPage.match failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _cancel() {
    _cancelled = true;
    StatementImportFlow.of(context).backToCapture();
  }

  void _retry() {
    setState(() {
      _error = null;
      _foundCount = 0;
      _done = false;
      _started = true;
      _cancelled = false;
    });
    _runExtract();
  }

  @override
  Widget build(BuildContext context) {
    final flow = StatementImportFlow.of(context);
    final account = flow.account;

    final t = Translations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _cancel,
        ),
        title: Text(_done ? t.statement_import.success.done : t.statement_import.processing.title),
      ),
      body: Column(
        children: [
          SiHeader(account: account),
          Expanded(
            child: _error != null
                ? _ErrorBody(
                    error: _error!,
                    onRetry: _retry,
                    onBack: _cancel,
                  )
                : _ProcessingBody(
                    scanCtrl: _scanCtrl,
                    foundCount: _foundCount,
                    done: _done,
                  ),
          ),
          if (_error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(t.statement_import.processing.cancel),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProcessingBody extends StatelessWidget {
  const _ProcessingBody({
    required this.scanCtrl,
    required this.foundCount,
    required this.done,
  });

  final AnimationController scanCtrl;
  final int foundCount;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ScanDocIllustration(controller: scanCtrl),
                const SizedBox(width: 14),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? t.statement_import.success.done : t.statement_import.processing.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      done
                          ? t.statement_import.processing.found(n: foundCount)
                          : t.statement_import.processing.analyzing,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.statement_import.ai_badge,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'VISTA PREVIA',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _SkeletonRow(controller: scanCtrl),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanDocIllustration extends StatelessWidget {
  const _ScanDocIllustration({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 70,
      height: 86,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Container(
              color: const Color(0xFFF4F2E8),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(6, (i) {
                  return Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (90 - i * 10) / 100,
                      child: Container(
                        height: 2,
                        color: const Color(0xFFB0A8B8),
                      ),
                    ),
                  );
                }),
              ),
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (_, _) {
                final t = controller.value;
                final y = (t < 0.5 ? t * 2 : (1 - t) * 2);
                return Positioned(
                  left: 0,
                  right: 0,
                  top: y * 80,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          cs.primary,
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.6),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final opacity = 0.4 + (controller.value * 0.4);
        final base = cs.onSurface.withValues(alpha: 0.08 * opacity);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(width: 42, height: 10, color: base),
              const SizedBox(width: 12),
              Expanded(child: Container(height: 10, color: base)),
              const SizedBox(width: 12),
              Container(width: 60, height: 10, color: base),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isTimeout = error is TimeoutException;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: cs.error,
          ),
          const SizedBox(height: 16),
          Text(
            t.statement_import.processing.error_generic,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isTimeout
                ? t.statement_import.processing.error_timeout
                : t.statement_import.processing.error_generic,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.refresh),
            label: Text(t.statement_import.processing.retry),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(t.statement_import.processing.back),
          ),
        ],
      ),
    );
  }
}
