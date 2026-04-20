import 'dart:async';

import 'package:permission_handler/permission_handler.dart';

/// Outcome of a voice session.
enum VoiceSessionStatus {
  /// Session ended normally with a final transcript (may be empty on silence).
  completed,

  /// Session aborted by the caller via [VoiceService.stop].
  cancelled,

  /// Session failed — see [VoiceSessionResult.errorMessage].
  error,
}

/// Final result returned by [VoiceService.stop].
class VoiceSessionResult {
  const VoiceSessionResult({
    required this.status,
    required this.transcript,
    this.errorMessage,
  });

  final VoiceSessionStatus status;

  /// Whatever was captured. May be empty on silence / low confidence — callers
  /// handle the empty-transcript edge case (see voice-input spec §4).
  final String transcript;

  /// Human-readable message when [status] is [VoiceSessionStatus.error].
  final String? errorMessage;

  bool get isOk => status == VoiceSessionStatus.completed;
  bool get isError => status == VoiceSessionStatus.error;
}

/// STT abstraction — implemented by `SpeechToTextVoiceService` today;
/// a future cloud-Whisper impl can drop in without touching callers.
abstract class VoiceService {
  /// Starts a recording session. Emits interim transcripts on [partials].
  ///
  /// [locale] defaults to `es_VE`. [maxDuration] defaults to 30s;
  /// the engine auto-finalizes after ~2s of silence.
  ///
  /// Throws [StateError] if a session is already active.
  Future<void> startSession({
    String locale = 'es_VE',
    Duration maxDuration = const Duration(seconds: 30),
  });

  /// Interim transcripts emitted while the user is speaking.
  Stream<String> get partials;

  /// Stops the current session and returns the final transcript.
  /// Safe to call when no session is active — returns a cancelled result.
  Future<VoiceSessionResult> stop();

  /// Whether a session is currently recording.
  bool get isListening;

  /// Requests [Permission.microphone], showing the OS prompt if needed.
  /// UI callers should show an explainer modal *before* calling this
  /// (see `voice_permission_dialog.dart`).
  Future<PermissionStatus> ensurePermission();

  /// Releases native engine resources. Idempotent.
  Future<void> dispose();
}
