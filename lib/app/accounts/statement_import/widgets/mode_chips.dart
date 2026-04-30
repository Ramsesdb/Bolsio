import 'package:flutter/material.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';

const List<String> kStatementImportModeOrder = [
  'missing',
  'income',
  'expense',
  'fees',
  'informative',
];

class ModeChips extends StatelessWidget {
  const ModeChips({
    super.key,
    required this.activeModes,
    required this.onChanged,
    required this.hasTrackedSince,
    required this.onInformativeBlocked,
  });

  final Set<String> activeModes;
  final ValueChanged<Set<String>> onChanged;
  final bool hasTrackedSince;
  final VoidCallback onInformativeBlocked;

  String _labelForMode(String id, Translations t) {
    switch (id) {
      case 'missing':
        return t.statement_import.modes.missing;
      case 'income':
        return t.statement_import.modes.income;
      case 'expense':
        return t.statement_import.modes.expense;
      case 'fees':
        return t.statement_import.modes.fees;
      case 'informative':
        return t.statement_import.modes.informative;
      default:
        return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MODO · COMBINABLE',
              style: tt.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (activeModes.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: cs.onSurfaceVariant,
                  textStyle: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => onChanged(<String>{}),
                child: Text(t.statement_import.review.clear),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final id in kStatementImportModeOrder) ...[
                _ModeChip(
                  label: _labelForMode(id, t),
                  selected: activeModes.contains(id),
                  onTap: () => _handleTap(id),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (activeModes.length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t.statement_import.review.and_label(n: activeModes.length),
              style: tt.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  void _handleTap(String id) {
    if (id == 'informative' &&
        !hasTrackedSince &&
        !activeModes.contains('informative')) {
      onInformativeBlocked();
      return;
    }
    final next = Set<String>.from(activeModes);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    onChanged(next);
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final bg = selected ? cs.primary : cs.surfaceContainerHighest;
    final fg = selected ? cs.onPrimary : cs.onSurface;
    final borderColor = selected
        ? cs.primary
        : cs.outlineVariant.withValues(alpha: 0.6);

    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: borderColor)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: tt.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
