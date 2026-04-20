import 'package:flutter/material.dart';
import 'package:wallex/app/chat/theme/wallex_ai_tokens.dart';

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
    final tokens = WallexAiTokens.of(context);
    final width = MediaQuery.of(context).size.width;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width * maxWidthFactor),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.accent,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(WallexAiTokens.bubbleRadius),
            topRight: Radius.circular(WallexAiTokens.bubbleRadius),
            bottomLeft: Radius.circular(WallexAiTokens.bubbleRadius),
            bottomRight: Radius.circular(WallexAiTokens.bubbleTailRadius),
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
