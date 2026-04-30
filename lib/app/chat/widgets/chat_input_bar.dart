import 'package:flutter/material.dart';
import 'package:kilatex/app/chat/theme/wallex_ai_tokens.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.isSending,
    required this.isUsingTools,
    required this.voiceAffordance,
    required this.onSend,
    this.onMicTap,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final bool isSending;
  final bool isUsingTools;
  final bool voiceAffordance;
  final VoidCallback onSend;
  final VoidCallback? onMicTap;
  final FocusNode? focusNode;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    widget.focusNode?.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChanged);
      widget.focusNode?.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.focusNode?.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final hasFocus = widget.focusNode?.hasFocus ?? false;
    if (hasFocus != _focused) {
      setState(() => _focused = hasFocus);
    }
  }

  bool get _hasText => widget.controller.text.trim().isNotEmpty;
  bool get _sendEnabled =>
      _hasText && !widget.isSending && !widget.isUsingTools;

  void _handleSendTap() {
    if (!_sendEnabled) return;
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = WallexAiTokens.of(context);
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final showMic = widget.voiceAffordance &&
        widget.onMicTap != null &&
        widget.controller.text.isEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomInset + 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _buildPill(tokens),
          ),
          const SizedBox(width: 8),
          // Reserve stable width so mic show/hide never shifts the send button.
          SizedBox(
            width: 44,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween<double>(begin: 0.6, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: showMic
                  ? _MicButton(
                      key: const ValueKey('mic'),
                      tokens: tokens,
                      onTap: widget.onMicTap!,
                      enabled: !widget.isSending && !widget.isUsingTools,
                    )
                  : const SizedBox.shrink(key: ValueKey('no-mic')),
            ),
          ),
          if (showMic) const SizedBox(width: 8),
          _SendButton(
            tokens: tokens,
            enabled: _sendEnabled,
            isSending: widget.isSending,
            onTap: _handleSendTap,
          ),
        ],
      ),
    );
  }

  Widget _buildPill(WallexAiTokens tokens) {
    final borderColor = _focused
        ? tokens.accent.withValues(alpha: 0.35)
        : tokens.border;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: WallexAiTokens.inputBarHeight,
        // ~4 lines * 14px * 1.55 height + vertical padding headroom.
        maxHeight: 140,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.bubbleAi,
          borderRadius: BorderRadius.circular(WallexAiTokens.inputBarRadius),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            enabled: !widget.isUsingTools,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) {
              if (_sendEnabled) widget.onSend();
            },
            style: tokens.bubbleBody,
            cursorColor: tokens.accent,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: widget.hint,
              hintStyle: TextStyle(
                color: tokens.muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    super.key,
    required this.tokens,
    required this.onTap,
    required this.enabled,
  });

  final WallexAiTokens tokens;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Grabar audio',
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: tokens.surfaceAlt,
          shape: CircleBorder(
            side: BorderSide(color: tokens.border, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.mic_rounded,
                size: 20,
                color: tokens.text.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.tokens,
    required this.enabled,
    required this.isSending,
    required this.onTap,
  });

  final WallexAiTokens tokens;
  final bool enabled;
  final bool isSending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Enviar mensaje',
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: (enabled || isSending) ? 1 : 0.45,
        child: Material(
          color: tokens.accent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: isSending
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(tokens.textOnUser),
                        ),
                      )
                    : Icon(
                        Icons.arrow_upward_rounded,
                        size: 20,
                        color: tokens.textOnUser,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
