import 'package:flutter/material.dart';
import 'package:wallex/app/chat/models/chat_card_payload.dart';
import 'package:wallex/app/chat/theme/wallex_ai_tokens.dart';

class BalanceCard extends StatelessWidget {
  const BalanceCard(this.payload, {super.key});

  final BalancePayload payload;

  @override
  Widget build(BuildContext context) {
    final tokens = WallexAiTokens.of(context);
    final width = MediaQuery.of(context).size.width;
    final breakdown = payload.breakdown;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width * 0.88),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tokens.surfaceAlt, tokens.bubbleAi],
          ),
          borderRadius: BorderRadius.circular(WallexAiTokens.cardRadius),
          border: Border.all(
            color: tokens.accent.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              payload.kickerLabel.toUpperCase(),
              style: tokens.cardKicker,
            ),
            const SizedBox(height: 6),
            _AmountDisplay(
              total: payload.total,
              currencyCode: payload.currencyCode,
              tokens: tokens,
            ),
            if (breakdown != null && breakdown.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(height: 1, color: tokens.border),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in breakdown)
                    _BreakdownCol(row: row, tokens: tokens),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({
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
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: tokens.accent,
            ),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: _withThousands(intPart),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w300,
              color: tokens.text,
              letterSpacing: -1.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: '.$decPart',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w300,
              color: tokens.text.withValues(alpha: 0.5),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  static String _withThousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _BreakdownCol extends StatelessWidget {
  const _BreakdownCol({required this.row, required this.tokens});

  final BalanceBreakdownRow row;
  final WallexAiTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          row.currencyCode.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: tokens.muted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          row.amount.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: tokens.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${(row.percent * 100).round()}%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.fainter,
          ),
        ),
      ],
    );
  }
}
