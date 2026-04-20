import 'package:flutter/material.dart';
import 'package:wallex/app/chat/models/chat_card_payload.dart';
import 'package:wallex/app/chat/theme/wallex_ai_tokens.dart';

class ExpenseCard extends StatelessWidget {
  const ExpenseCard(this.payload, {super.key});

  final ExpensePayload payload;

  @override
  Widget build(BuildContext context) {
    final tokens = WallexAiTokens.of(context);
    final width = MediaQuery.of(context).size.width;

    // Cap at 5 rows, collapse overflow into "Otros".
    final rows = _collapseRows(payload.categories);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width * 0.88),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.bubbleAi,
          borderRadius: BorderRadius.circular(WallexAiTokens.cardRadius),
          border: Border.all(color: tokens.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payload.kickerLabel.toUpperCase(),
                        style: tokens.cardKicker,
                      ),
                      const SizedBox(height: 4),
                      _TotalAmount(
                        total: payload.total,
                        currencyCode: payload.currencyCode,
                        tokens: tokens,
                      ),
                    ],
                  ),
                ),
                if (payload.deltaPct != null)
                  _DeltaPill(deltaPct: payload.deltaPct!, tokens: tokens),
              ],
            ),
            const SizedBox(height: 14),
            _StackedBar(rows: rows),
            const SizedBox(height: 12),
            ...List.generate(rows.length, (i) {
              final r = rows[i];
              return Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: _CategoryRow(row: r, tokens: tokens),
              );
            }),
          ],
        ),
      ),
    );
  }

  List<ExpenseCategoryRow> _collapseRows(List<ExpenseCategoryRow> src) {
    if (src.length <= 5) return src;
    final top = src.take(4).toList();
    final rest = src.skip(4);
    double amount = 0;
    double percent = 0;
    for (final r in rest) {
      amount += r.amount;
      percent += r.percent;
    }
    top.add(ExpenseCategoryRow(
      label: 'Otros',
      dotColor: top.last.dotColor,
      amount: amount,
      percent: percent,
    ));
    return top;
  }
}

class _TotalAmount extends StatelessWidget {
  const _TotalAmount({
    required this.total,
    required this.currencyCode,
    required this.tokens,
  });

  final double total;
  final String currencyCode;
  final WallexAiTokens tokens;

  @override
  Widget build(BuildContext context) {
    final abs = total.abs();
    final intPart = abs.truncate();
    final decPart = ((abs - intPart) * 100).round().toString().padLeft(2, '0');

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontFamily: null),
        children: [
          TextSpan(
            text: '\$',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: tokens.accent,
            ),
          ),
          TextSpan(
            text: intPart.toString(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: tokens.text,
              letterSpacing: -0.8,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: '.$decPart',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: tokens.text.withValues(alpha: 0.5),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.deltaPct, required this.tokens});

  final double deltaPct;
  final WallexAiTokens tokens;

  @override
  Widget build(BuildContext context) {
    final positive = deltaPct >= 0;
    final pillColor = positive ? tokens.danger : tokens.success;
    final sign = positive ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: pillColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(WallexAiTokens.chipRadius),
      ),
      child: Text(
        '$sign${deltaPct.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: pillColor,
        ),
      ),
    );
  }
}

class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.rows});

  final List<ExpenseCategoryRow> rows;

  @override
  Widget build(BuildContext context) {
    final segments = rows.where((r) => r.percent >= 0.005).toList();
    if (segments.isEmpty) return const SizedBox(height: 8);
    return ClipRRect(
      borderRadius: BorderRadius.circular(WallexAiTokens.chipRadius),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final r in segments)
              Expanded(
                flex: (r.percent * 1000).round(),
                child: Container(color: r.dotColor),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.row, required this.tokens});

  final ExpenseCategoryRow row;
  final WallexAiTokens tokens;

  @override
  Widget build(BuildContext context) {
    final abs = row.amount.abs();
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: row.dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            row.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tokens.text,
            ),
          ),
        ),
        Text(
          '\$${abs.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: tokens.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${(row.percent * 100).round()}%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.muted,
          ),
        ),
      ],
    );
  }
}
