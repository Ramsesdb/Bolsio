import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:wallex/app/chat/widgets/voice_action_buttons.dart';
import 'package:wallex/core/services/voice/voice_service.dart';
import 'package:wallex/core/services/voice/voice_service_speech_to_text.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Wallex "Liquid Glass" voice capture sheet.
///
/// Public contract (preserved):
///  - returns a String on completion (may be empty for silence/VAD auto-stop)
///  - returns null when the user cancels or STT errors out
///
/// The visual skin (blurred translucent sheet, 3-ring mic pulse, animated
/// transcript, mustard accent) comes from the Wallex Voice Sheets design bundle.
Future<String?> showVoiceRecordOverlay(
  BuildContext context, {
  VoiceService? service,
  String locale = 'es_VE',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    // Our glass panel draws its own drag handle + radii — suppress the default.
    showDragHandle: false,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (sheetContext) {
      return _VoiceRecordOverlay(
        service: service ?? SpeechToTextVoiceService.instance,
        locale: locale,
      );
    },
  );
}

// ──────────────────────────────────────────────────────────────────────
// Wallex palette tokens (neutrals only). The accent is resolved per-build
// from Theme.of(context).colorScheme.primary so the voice overlay follows
// the user's selected accent (or Material You dynamic color) rather than
// the legacy hardcoded mustard.
// ──────────────────────────────────────────────────────────────────────
const Color _kSheetTint = Color.fromRGBO(22, 22, 22, 0.62);
const Color _kHairline = Color.fromRGBO(255, 255, 255, 0.08);
const Color _kInnerShineTop = Color.fromRGBO(255, 255, 255, 0.08);

Color _kAccentOf(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

class _VoiceRecordOverlay extends StatefulWidget {
  const _VoiceRecordOverlay({required this.service, required this.locale});

  final VoiceService service;
  final String locale;

  @override
  State<_VoiceRecordOverlay> createState() => _VoiceRecordOverlayState();
}

enum _OverlayState { listening, processing, error }

class _VoiceRecordOverlayState extends State<_VoiceRecordOverlay>
    with TickerProviderStateMixin {
  _OverlayState _state = _OverlayState.listening;
  String _partial = '';
  String? _errorMessage;

  StreamSubscription<String>? _partialSub;

  /// Single master clock driving the 3 staggered pulse rings.
  /// Period = 2000ms when listening, 4000ms when processing (slower feel).
  late final AnimationController _pulseCtrl;

  /// Blinking caret for the live transcript.
  late final AnimationController _caretCtrl;

  /// Spinner for the "Procesando…" pill.
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _caretCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _startListening();
  }

  Future<void> _startListening() async {
    await _partialSub?.cancel();
    _partialSub = null;

    try {
      // IMPORTANT: startSession() creates the internal partials StreamController.
      // We MUST subscribe AFTER startSession returns, otherwise `service.partials`
      // hands back `const Stream<String>.empty()` and every interim transcript is
      // dropped on the floor (that was the "words never appear on screen" bug).
      await widget.service.startSession(locale: widget.locale);
    } on StateError {
      await widget.service.stop();
      try {
        await widget.service.startSession(locale: widget.locale);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _state = _OverlayState.error;
          _errorMessage = e.toString();
        });
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _OverlayState.error;
        _errorMessage = e.toString();
      });
      return;
    }

    _partialSub = widget.service.partials.listen(
      (partial) {
        if (!mounted) return;
        debugPrint('VoiceOverlay.partial="$partial"');
        setState(() => _partial = partial);
      },
      onDone: () {
        // Engine closed the stream (VAD auto-stop or final result). Only auto-
        // finalize if we have a non-empty transcript; otherwise keep the sheet
        // open so the user can retry or cancel manually. This prevents the
        // "sheet closes unexpectedly with empty transcript" symptom.
        if (!mounted) return;
        if (_partial.trim().isNotEmpty && _state == _OverlayState.listening) {
          unawaited(_finalize());
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _finalize() async {
    // Visually flip to "processing" while we harvest the final transcript.
    if (mounted && _state == _OverlayState.listening) {
      setState(() => _state = _OverlayState.processing);
      _pulseCtrl.duration = const Duration(milliseconds: 4000);
      _pulseCtrl.reset();
      unawaited(_pulseCtrl.repeat());
    }

    final result = await widget.service.stop();
    if (!mounted) return;
    final t = Translations.of(context).wallex_ai;
    debugPrint(
      'VoiceOverlay.finalize status=${result.status} '
      'transcript="${result.transcript}"',
    );

    switch (result.status) {
      case VoiceSessionStatus.completed:
        Navigator.of(context).pop(result.transcript);
      case VoiceSessionStatus.cancelled:
        // User tapped "Listo" mid-session — the engine was still listening so
        // the service resolves as cancelled, but we have a valid partial
        // transcript the user wants to submit. Don't drop it on the floor.
        if (result.transcript.trim().isNotEmpty) {
          Navigator.of(context).pop(result.transcript);
        } else {
          Navigator.of(context).pop(null);
        }
      case VoiceSessionStatus.error:
        setState(() {
          _state = _OverlayState.error;
          _errorMessage = _mapErrorMessage(result.errorMessage, t);
        });
        _pulseCtrl.duration = const Duration(milliseconds: 2000);
        _pulseCtrl.reset();
        unawaited(_pulseCtrl.repeat());
    }
  }

  String _mapErrorMessage(String? raw, TranslationsWallexAiEn t) {
    if (raw == null || raw.isEmpty) return t.voice_error_fallback;
    final lower = raw.toLowerCase();
    if (lower.contains('internet') || lower.contains('network')) {
      return t.voice_offline_hint;
    }
    if (lower.contains('not available') ||
        lower.contains('unavailable') ||
        lower.contains('not supported')) {
      return t.voice_stt_unavailable;
    }
    return raw;
  }

  Future<void> _cancel() async {
    await widget.service.stop();
    if (!mounted) return;
    Navigator.of(context).pop(null);
  }

  Future<void> _retry() async {
    setState(() {
      _state = _OverlayState.listening;
      _partial = '';
      _errorMessage = null;
    });
    _pulseCtrl.duration = const Duration(milliseconds: 2000);
    _pulseCtrl.reset();
    unawaited(_pulseCtrl.repeat());
    await _startListening();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _caretCtrl.dispose();
    _spinCtrl.dispose();
    _partialSub?.cancel();
    unawaited(widget.service.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context).wallex_ai;
    final mq = MediaQuery.of(context);
    // 62% of screen height per spec; clamp so it never exceeds available space.
    final sheetHeight = (mq.size.height * 0.62).clamp(440.0, 720.0).toDouble();

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: sheetHeight,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _kSheetTint,
                border: Border(
                  top: BorderSide(color: _kHairline, width: 0.5),
                  left: BorderSide(color: _kHairline, width: 0.5),
                  right: BorderSide(color: _kHairline, width: 0.5),
                ),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: _kInnerShineTop,
                    offset: Offset(0, 1),
                    blurRadius: 0,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Subtle gradient overlay to give the glass depth.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.02),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      const SizedBox(height: 10),
                      // Drag handle
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _StatusBadge(state: _state, t: t),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 96),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _MicButton(
                                pulseCtrl: _pulseCtrl,
                                active: _state == _OverlayState.listening,
                                isError: _state == _OverlayState.error,
                              ),
                              const SizedBox(height: 28),
                              _LiveTranscript(
                                text: _state == _OverlayState.error
                                    ? (_errorMessage ?? t.voice_error_fallback)
                                    : (_partial.isEmpty
                                        ? t.voice_listening_hint
                                        : _partial),
                                showCaret: _state == _OverlayState.listening &&
                                    _partial.isNotEmpty,
                                caretCtrl: _caretCtrl,
                                dim: _partial.isEmpty &&
                                    _state != _OverlayState.error,
                              ),
                              if (_state == _OverlayState.processing) ...[
                                const SizedBox(height: 20),
                                _ProcessingPill(
                                  spinCtrl: _spinCtrl,
                                  label: t.voice_processing,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Bottom action row — unified X + Enviar pair.
                  // In the error state we layer a "Reintentar" text button
                  // above the row so the retry affordance survives the
                  // switch to the shared widget (which only exposes
                  // cancel + send, not retry).
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 20),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_state == _OverlayState.error)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _TextActionButton(
                                    label: t.voice_retry,
                                    color: _kAccentOf(context),
                                    fontWeight: FontWeight.w700,
                                    onTap: _retry,
                                  ),
                                ),
                              ),
                            VoiceActionButtons(
                              onCancel: _cancel,
                              onSend: _state == _OverlayState.error
                                  ? null
                                  : _finalize,
                              isSending: _state == _OverlayState.processing,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Status badge ("● Escuchando" / "◷ Procesando" / "⚠ Error")
// ──────────────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state, required this.t});
  final _OverlayState state;
  final TranslationsWallexAiEn t;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (state) {
      case _OverlayState.listening:
        color = _kAccentOf(context);
        label = '● ${t.voice_listening_title}';
      case _OverlayState.processing:
        color = Colors.white.withValues(alpha: 0.45);
        label = '○ ${t.voice_processing}';
      case _OverlayState.error:
        color = const Color(0xFFF75959);
        label = '⚠ ${t.voice_error_title}';
    }
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 240),
      style: TextStyle(
        fontSize: 13,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      child: Text(label.toUpperCase()),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Mic button with 3 concentric pulse rings
// ──────────────────────────────────────────────────────────────────────
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.pulseCtrl,
    required this.active,
    required this.isError,
  });

  final AnimationController pulseCtrl;
  final bool active;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final accent =
        isError ? const Color(0xFFF75959) : _kAccentOf(context);
    final accentSoft = accent.withValues(alpha: 0.33);
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 3 staggered rings
          AnimatedBuilder(
            animation: pulseCtrl,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: List.generate(3, (i) {
                  // Each ring leads the next by 0.30 of the cycle (~600ms of 2s).
                  final offset = i * 0.30;
                  var t = (pulseCtrl.value + offset) % 1.0;
                  // easeOutQuart ≈ CSS cubic-bezier(.22,1,.36,1)
                  final eased = Curves.easeOutQuart.transform(t);
                  final scale = 1.0 + 0.85 * eased;
                  final opacity = (1 - t) * 0.55;
                  return IgnorePointer(
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent.withValues(alpha: opacity),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          // Core mic circle
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                radius: 0.9,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.02),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(color: accentSoft, width: 1),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.20),
                  blurRadius: 60,
                  offset: const Offset(0, 20),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.04),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.18),
                  offset: const Offset(0, 1),
                  blurRadius: 0,
                ),
              ],
            ),
            child: AnimatedScale(
              scale: active ? 1.0 : 0.94,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: Icon(
                isError ? Icons.error_outline_rounded : Icons.mic_rounded,
                color: accent,
                size: 64,
                shadows: [
                  Shadow(
                    color: accent.withValues(alpha: 0.60),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Live transcript with per-word fade-in stagger + blinking caret
// ──────────────────────────────────────────────────────────────────────
class _LiveTranscript extends StatelessWidget {
  const _LiveTranscript({
    required this.text,
    required this.showCaret,
    required this.caretCtrl,
    required this.dim,
  });

  final String text;
  final bool showCaret;
  final AnimationController caretCtrl;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    final color = dim
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.white;
    final wordCount = words.length;

    // NOTE: the old impl used a `Wrap` of per-word `Text` widgets. `Wrap`
    // shrink-wraps its width to its children, so `WrapAlignment.center` only
    // centers the *internal* runs — the Wrap itself remained left-biased inside
    // the outer column whenever its intrinsic width was narrower than the
    // available width. Visually this showed up as the transcript hugging the
    // left edge and overflowing leftward as it grew. Switching to a single
    // `Text.rich` with `TextAlign.center` + full-width `SizedBox` makes the
    // text block occupy the whole centered strip and wraps cleanly on word
    // boundaries, with the caret pinned to the end of the last line.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 88),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: SizedBox(
          width: double.infinity,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              // Key by word count so the fade only triggers when new words
              // arrive, NOT on every character change within a word. Keeps the
              // transcript visible and stable during rapid partial updates.
              child: Align(
                key: ValueKey<int>(wordCount),
                alignment: Alignment.center,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: words.join(' ')),
                      if (showCaret) ...[
                        const TextSpan(text: ' '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: FadeTransition(
                            opacity: TweenSequence<double>([
                              TweenSequenceItem(
                                  tween: ConstantTween(1.0), weight: 50),
                              TweenSequenceItem(
                                  tween: ConstantTween(0.0), weight: 50),
                            ]).animate(caretCtrl),
                            child: Container(
                              width: 3,
                              height: 26,
                              decoration: BoxDecoration(
                                color: _kAccentOf(context),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  textAlign: TextAlign.center,
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    height: 1.22,
                    letterSpacing: -0.6,
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

// ──────────────────────────────────────────────────────────────────────
// "Procesando…" pill with spinner
// ──────────────────────────────────────────────────────────────────────
class _ProcessingPill extends StatelessWidget {
  const _ProcessingPill({required this.spinCtrl, required this.label});

  final AnimationController spinCtrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: RotationTransition(
              turns: spinCtrl,
              child: CustomPaint(
                painter: _SpinnerArcPainter(accent: _kAccentOf(context)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              letterSpacing: -0.1,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinnerArcPainter extends CustomPainter {
  _SpinnerArcPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.25;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withValues(alpha: 0.15);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = accent;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // -90deg
      1.5708, // 90deg sweep
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerArcPainter old) => old.accent != accent;
}

// ──────────────────────────────────────────────────────────────────────
// Flat text action buttons for the bottom row
// ──────────────────────────────────────────────────────────────────────
class _TextActionButton extends StatelessWidget {
  const _TextActionButton({
    required this.label,
    required this.color,
    required this.fontWeight,
    required this.onTap,
  });

  final String label;
  final Color color;
  final FontWeight fontWeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: fontWeight,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }
}
