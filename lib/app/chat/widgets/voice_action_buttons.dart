import 'package:flutter/material.dart';
import 'package:bolsio/app/chat/theme/bolsio_ai_tokens.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

/// Shared cancel-X + "Enviar" pill pair used across every voice-recording
/// surface in the app (chat voice overlay, voice quick-expense overlay,
/// review sheet). Extracted from the Claude Design v2 `VariantB_Voice`
/// control bar.
///
/// Tokens (spacing, radii, sizes) match the design spec; colors defer to
/// [BolsioAiTokens] so the buttons follow the user's accent.
class VoiceActionButtons extends StatelessWidget {
  const VoiceActionButtons({
    super.key,
    required this.onCancel,
    required this.onSend,
    this.sendLabel,
    this.isSending = false,
  });

  final VoidCallback onCancel;

  /// `null` disables the Enviar pill (used when the transcript is empty
  /// or the surface is still initializing).
  final VoidCallback? onSend;

  /// Override for the pill label. Defaults to the i18n `submit` key
  /// ("Enviar" in es, "Send" in en).
  final String? sendLabel;

  /// Shows an in-pill spinner and suppresses taps.
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    final tokens = BolsioAiTokens.of(context);
    final t = Translations.of(context);
    final label = sendLabel ?? t.ui_actions.submit;
    final sendEnabled = onSend != null && !isSending;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _CancelCircle(
          onTap: isSending ? null : onCancel,
          tokens: tokens,
        ),
        const SizedBox(width: 12),
        _SendPill(
          label: label,
          enabled: sendEnabled,
          isSending: isSending,
          onTap: sendEnabled ? onSend : null,
          tokens: tokens,
        ),
      ],
    );
  }
}

class _CancelCircle extends StatelessWidget {
  const _CancelCircle({required this.onTap, required this.tokens});

  final VoidCallback? onTap;
  final BolsioAiTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cancelar grabación',
      child: Material(
        color: tokens.surfaceAlt.withValues(alpha: 0.5),
        shape: CircleBorder(
          side: BorderSide(color: tokens.border.withValues(alpha: 0.4), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.close,
              size: 20,
              color: tokens.text.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendPill extends StatelessWidget {
  const _SendPill({
    required this.label,
    required this.enabled,
    required this.isSending,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final bool enabled;
  final bool isSending;
  final VoidCallback? onTap;
  final BolsioAiTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Enviar grabación',
      child: Opacity(
        opacity: enabled || isSending ? 1.0 : 0.45,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            shadows: [
              BoxShadow(
                color: tokens.accent.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 2),
              ),
              BoxShadow(
                color: tokens.accent.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: tokens.accent,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Center(
                    child: isSending
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                tokens.textOnUser,
                              ),
                            ),
                          )
                        : Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: tokens.textOnUser,
                              letterSpacing: -0.1,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
