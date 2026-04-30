import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bolsio/core/database/app_db.dart';
import 'package:bolsio/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:bolsio/core/services/statement_import/models/matching_result.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

class RowTile extends StatelessWidget {
  const RowTile({
    super.key,
    required this.result,
    required this.selected,
    required this.onToggle,
    this.currency,
  });

  final MatchingResult result;
  final bool selected;
  final VoidCallback onToggle;
  final CurrencyInDB? currency;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final row = result.row;

    final isIncome = row.kind == 'income';
    final isFee = row.kind == 'fee';

    final IconData kindIcon = isIncome
        ? Icons.arrow_downward_rounded
        : isFee
            ? Icons.paid_outlined
            : Icons.arrow_upward_rounded;

    final Color kindColor = isIncome
        ? Colors.green.shade400
        : isFee
            ? cs.onSurfaceVariant
            : cs.onSurface;

    final amountColor = isIncome
        ? Colors.green.shade400
        : cs.error;

    final signedAmount = isIncome ? row.amount : -row.amount;
    final sign = isIncome ? '+' : '-';

    final tile = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: selected,
              onChanged: (_) => onToggle(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Icon(kindIcon, size: 20, color: kindColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    row.description.isEmpty ? '(sin descripción)' : row.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _TagsRow(result: result),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sign,
                      style: tt.titleSmall?.copyWith(
                        color: amountColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 2),
                    CurrencyDisplayer(
                      amountToConvert: signedAmount.abs(),
                      currency: currency,
                      followPrivateMode: false,
                      integerStyle: tt.titleSmall!.copyWith(
                        color: amountColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (result.existsInApp) {
      return Opacity(opacity: 0.6, child: tile);
    }
    return tile;
  }
}

class _TagsRow extends StatelessWidget {
  const _TagsRow({required this.result});

  final MatchingResult result;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;
    final row = result.row;
    final dateLabel = DateFormat('dd/MM HH:mm').format(row.date);

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _MiniTag(
          label: dateLabel,
          fg: cs.onSurfaceVariant,
          bg: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        ),
        if (row.kind == 'fee')
          _MiniTag(
            label: t.statement_import.review.tag_fee,
            fg: Colors.orange.shade400,
            bg: Colors.orange.withValues(alpha: 0.12),
          ),
        if (result.existsInApp)
          _MiniTag(
            label: t.statement_import.review.tag_exists,
            fg: cs.primary,
            bg: cs.primary.withValues(alpha: 0.12),
          ),
        if (result.isPreFresh)
          _MiniTag(
            label: t.statement_import.review.tag_prefresh,
            fg: Colors.blue.shade300,
            bg: Colors.blue.withValues(alpha: 0.12),
          ),
      ],
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({
    required this.label,
    required this.fg,
    required this.bg,
  });

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}
