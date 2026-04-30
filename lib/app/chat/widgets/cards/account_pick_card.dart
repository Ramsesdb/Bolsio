import 'package:flutter/material.dart';
import 'package:kilatex/app/chat/models/chat_card_payload.dart';
import 'package:kilatex/app/chat/theme/wallex_ai_tokens.dart';
import 'package:kilatex/app/chat/widgets/hex_tile.dart';

class AccountPickCard extends StatelessWidget {
  const AccountPickCard(
    this.payload, {
    super.key,
    required this.onTap,
  });

  final AccountPickPayload payload;
  final void Function(String accountId) onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = WallexAiTokens.of(context);
    final width = MediaQuery.of(context).size.width;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width * 0.88),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.bubbleAi,
          borderRadius: BorderRadius.circular(WallexAiTokens.cardRadius),
          border: Border.all(color: tokens.border, width: 1),
        ),
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final item in payload.accounts)
              _AccountTile(
                item: item,
                tokens: tokens,
                onTap: () => onTap(item.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.item,
    required this.tokens,
    required this.onTap,
  });

  final AccountPickItem item;
  final WallexAiTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.surfaceAlt,
      borderRadius: BorderRadius.circular(WallexAiTokens.innerCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WallexAiTokens.innerCardRadius),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              HexTile(
                size: 30,
                fill: item.tileColor,
                child: Text(
                  item.initial,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatBalance(item.balance, item.currencyCode),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tokens.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBalance(double balance, String code) {
    final abs = balance.abs();
    final sign = balance < 0 ? '-' : '';
    return '$sign${_symbolFor(code)}${abs.toStringAsFixed(2)}';
  }

  String _symbolFor(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'VES':
      case 'VEF':
        return 'Bs ';
      default:
        return '$code ';
    }
  }
}
