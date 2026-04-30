import 'package:flutter/material.dart';
import 'package:kilatex/app/accounts/account_form.dart';
import 'package:kilatex/app/accounts/statement_import/statement_import_flow.dart';
import 'package:kilatex/app/accounts/statement_import/widgets/counter.dart';
import 'package:kilatex/app/accounts/statement_import/widgets/mode_chips.dart';
import 'package:kilatex/app/accounts/statement_import/widgets/row_tile.dart';
import 'package:kilatex/app/accounts/statement_import/widgets/si_header.dart';
import 'package:kilatex/core/presentation/widgets/inline_info_card.dart';
import 'package:kilatex/core/routes/route_utils.dart';
import 'package:kilatex/core/services/statement_import/models/matching_result.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  Set<String> _activeModes = <String>{};
  final Set<String> _deselectedRowIds = <String>{};

  List<MatchingResult> get _results {
    return StatementImportFlow.of(context).matchingResults ?? const [];
  }

  bool _rowPassesActiveModes(MatchingResult r) {
    if (_activeModes.isEmpty) return true;
    if (_activeModes.contains('missing') && r.existsInApp) return false;
    if (_activeModes.contains('income') && r.row.kind != 'income') return false;
    if (_activeModes.contains('expense') && r.row.kind != 'expense') {
      return false;
    }
    if (_activeModes.contains('fees') && r.row.kind != 'fee') return false;
    if (_activeModes.contains('informative') && !r.isPreFresh) return false;
    return true;
  }

  List<MatchingResult> get _visibleResults =>
      _results.where(_rowPassesActiveModes).toList();

  List<MatchingResult> get _selectedVisibleResults => _visibleResults
      .where((r) => !_deselectedRowIds.contains(r.row.id))
      .toList();

  bool get _allVisibleSelected =>
      _visibleResults.isNotEmpty &&
      _visibleResults.every((r) => !_deselectedRowIds.contains(r.row.id));

  void _toggleRow(String id) {
    setState(() {
      if (_deselectedRowIds.contains(id)) {
        _deselectedRowIds.remove(id);
      } else {
        _deselectedRowIds.add(id);
      }
    });
  }

  void _toggleAll() {
    setState(() {
      if (_allVisibleSelected) {
        for (final r in _visibleResults) {
          _deselectedRowIds.add(r.row.id);
        }
      } else {
        for (final r in _visibleResults) {
          _deselectedRowIds.remove(r.row.id);
        }
      }
    });
  }

  Future<void> _promptInformativeBlocked() async {
    final flow = StatementImportFlow.of(context);
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.statement_import.review.fresh_start_dialog_title),
        content: Text(t.statement_import.review.fresh_start_dialog_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.ui_actions.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.primary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.statement_import.review.fresh_start_configure),
          ),
        ],
      ),
    );

    if (!mounted || proceed != true) return;

    await RouteUtils.pushRoute(AccountFormPage(account: flow.account));
    if (!mounted) return;
    await flow.refreshAccount();
    if (!mounted) return;
    setState(() {});
  }

  void _onModesChanged(Set<String> next) {
    setState(() => _activeModes = next);
  }

  void _continue() {
    final flow = StatementImportFlow.of(context);
    final approved = _selectedVisibleResults;
    if (approved.isEmpty) return;
    flow.goToConfirm(approved: approved, modes: _activeModes);
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final flow = StatementImportFlow.of(context);
    final account = flow.account;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final results = _results;
    final hasTrackedSince = account.trackedSince != null;

    final filteredCount = _selectedVisibleResults.length;
    final total = results.length;

    final trackedSince = account.trackedSince;
    final showWarning = _activeModes.contains('informative') &&
        trackedSince != null &&
        _selectedVisibleResults.any((r) => !r.row.date.isBefore(trackedSince));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => StatementImportFlow.of(context).backToCapture(),
        ),
        title: Text(t.statement_import.review.title),
        actions: [
          if (_visibleResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _toggleAll,
                child: Text(
                  _allVisibleSelected
                      ? t.statement_import.review.toggle_none
                      : t.statement_import.review.toggle_all,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: results.isEmpty
          ? _EmptyState(
              onBack: () =>
                  StatementImportFlow.of(context).backToCapture(),
            )
          : Column(
              children: [
                SiHeader(account: account),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      ModeChips(
                        activeModes: _activeModes,
                        onChanged: _onModesChanged,
                        hasTrackedSince: hasTrackedSince,
                        onInformativeBlocked: _promptInformativeBlocked,
                      ),
                      const SizedBox(height: 12),
                      StatementImportCounter(
                        filtered: filteredCount,
                        total: total,
                      ),
                      if (showWarning) ...[
                        const SizedBox(height: 10),
                        InlineInfoCard(
                          mode: InlineInfoCardMode.warn,
                          text: t.statement_import.review.informative_warning,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'MOVIMIENTOS DETECTADOS',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Seleccionados $filteredCount',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...results.map((r) {
                        final visible = _rowPassesActiveModes(r);
                        final selected =
                            !_deselectedRowIds.contains(r.row.id);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: visible ? 1.0 : 0.3,
                            child: IgnorePointer(
                              ignoring: !visible,
                              child: RowTile(
                                result: r,
                                selected: selected && visible,
                                onToggle: () => _toggleRow(r.row.id),
                                currency: account.currency,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: FilledButton(
                      onPressed: filteredCount == 0 ? null : _continue,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(
                        t.statement_import.review.continue_cta(n: filteredCount),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 72, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              t.statement_import.review.empty,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Prueba con una imagen más nítida o un estado de cuenta distinto.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(t.statement_import.review.clear),
            ),
          ],
        ),
      ),
    );
  }
}
