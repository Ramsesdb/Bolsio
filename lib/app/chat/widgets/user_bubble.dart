import 'package:flutter/material.dart';
import 'package:bolsio/app/chat/theme/bolsio_ai_tokens.dart';

class UserBubble extends StatelessWidget {
  const UserBubble({
    super.key,
    required this.text,
    this.maxWidthFactor = 0.78,
  });

  final String text;
  final double maxWidthFactor;

  @override
  Widget build(BuildContext context) {
    final tokens = BolsioAiTokens.of(context);
    final width = MediaQuery.of(context).size.width;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width * maxWidthFactor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.accent,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(BolsioAiTokens.bubbleRadius),
            topRight: Radius.circular(BolsioAiTokens.bubbleRadius),
            bottomLeft: Radius.circular(BolsioAiTokens.bubbleRadius),
            bottomRight: Radius.circular(BolsioAiTokens.bubbleTailRadius),
          ),
        ),
        child: Text(
          text,
          style: tokens.bubbleBodyOnUser.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
