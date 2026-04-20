import 'package:flutter/material.dart';
import 'package:wallex/app/chat/theme/wallex_ai_tokens.dart';

class AiBubble extends StatelessWidget {
  const AiBubble({
    super.key,
    required this.child,
    this.isStreaming = false,
    this.maxWidthFactor = 0.78,
  });

  final Widget child;
  final bool isStreaming;
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
          color: tokens.bubbleAi,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(WallexAiTokens.bubbleTailRadius),
            topRight: Radius.circular(WallexAiTokens.bubbleRadius),
            bottomLeft: Radius.circular(WallexAiTokens.bubbleRadius),
            bottomRight: Radius.circular(WallexAiTokens.bubbleRadius),
          ),
          border: Border.all(color: tokens.border, width: 0.5),
        ),
        child: isStreaming
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: child),
                  const SizedBox(width: 2),
                  _StreamingCursor(color: tokens.accent),
                ],
              )
            : child,
      ),
    );
  }
}

class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor({required this.color});

  final Color color;

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: WallexAiTokens.streamingCursorBlink,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(width: 2, height: 16, color: widget.color),
    );
  }
}
