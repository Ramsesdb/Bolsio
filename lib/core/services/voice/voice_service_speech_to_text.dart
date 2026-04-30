import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:kilatex/core/services/voice/voice_service.dart';

/// `speech_to_text`-backed [VoiceService] implementation.
///
/// Uses the singleton `VoiceService.instance` pattern — matches
/// `NexusAiService`, `AutoCategorizationService`, etc.
class SpeechToTextVoiceService implements VoiceService {
  SpeechToTextVoiceService({stt.SpeechToText? engine})
      : _engine = engine ?? stt.SpeechToText();

  /// Shared singleton. Use this everywhere except tests (which use
  /// `FakeVoiceService`).
  static final SpeechToTextVoiceService instance = SpeechToTextVoiceService();

  final stt.SpeechToText _engine;

  StreamController<String>? _partialsCtrl;
  String _lastTranscript = '';
  bool _engineInitialized = false;
  bool _cancelledByCaller = false;
  Completer<VoiceSessionResult>? _sessionCompleter;

  /// Snapshot of the last completed session result. Kept so [stop] can return
  /// the real transcript when the engine auto-resolved via VAD before the UI
  /// got around to calling [stop] (the main happy path for dictation).
  VoiceSessionResult? _lastResult;

  /// Resolved locale id we last handed to the engine — kept so tests / logs
  /// can inspect the fallback result (e.g. `es_VE` requested → `es_US` used).
  String? _resolvedLocaleId;
  String? get lastResolvedLocaleId => _resolvedLocaleId;

  @override
  Stream<String> get partials =>
      _partialsCtrl?.stream ?? const Stream<String>.empty();

  @override
  bool get isListening => _engine.isListening;

  @override
  Future<PermissionStatus> ensurePermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return status;
    status = await Permission.microphone.request();
    return status;
  }

  @override
  Future<void> startSession({
    String locale = 'es_VE',
    Duration maxDuration = const Duration(seconds: 30),
  }) async {
    if (_engine.isListening || _sessionCompleter != null) {
      throw StateError('VoiceService: a session is already active');
    }

    if (!_engineInitialized) {
      final available = await _engine.initialize(
        onError: _onEngineError,
        onStatus: _onEngineStatus,
      );
      if (!available) {
        throw StateError('VoiceService: STT engine unavailable on this device');
      }
      _engineInitialized = true;
    }

    _partialsCtrl = StreamController<String>.broadcast();
    _lastTranscript = '';
    _lastResult = null;
    _cancelledByCaller = false;
    _sessionCompleter = Completer<VoiceSessionResult>();

    // Resolve the locale id: Xiaomi / MIUI devices often ship with `es_US`,
    // `es_MX`, `es_419` etc. but NOT `es_VE`. When `speech_to_text` receives
    // a locale id the device doesn't have, the SODA recognizer silently fails
    // ("Failed to get language pack of required locale: error 12") and the
    // session resolves with NO_SPEECH_DETECTED / empty transcript.
    final resolvedLocale = await _resolveLocale(locale);
    _resolvedLocaleId = resolvedLocale;
    debugPrint(
      'VoiceService.startSession requested=$locale resolved=$resolvedLocale',
    );

    await _engine.listen(
      onResult: _onEngineResult,
      localeId: resolvedLocale,
      listenFor: maxDuration,
      // Default is 800ms which cuts users off mid-sentence. The engine's VAD
      // counter resets on each acoustic event, so 6s gives comfortable headroom
      // for the user to finish a phrase like "gasté 12 dólares en gasolina"
      // without the sheet auto-closing during a natural mid-sentence breath.
      pauseFor: const Duration(seconds: 6),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  /// Picks the closest locale the device actually supports.
  ///
  /// Preference order:
  ///  1. Exact match (case-insensitive, `_`/`-` normalized).
  ///  2. Same language, same region family (e.g. `es_VE` → any `es_*`).
  ///  3. Same language only.
  ///  4. Whatever the engine advertises as the system locale.
  ///  5. Fall back to the originally-requested string (engine will error out,
  ///     and we surface that error via [_onEngineError]).
  Future<String> _resolveLocale(String requested) async {
    try {
      final available = await _engine.locales();
      if (available.isEmpty) {
        debugPrint('VoiceService: engine reports NO available locales '
            '(Android 11+ <queries> missing?)');
        return requested;
      }
      String norm(String s) => s.toLowerCase().replaceAll('-', '_');
      final reqN = norm(requested);
      final reqLang =
          reqN.contains('_') ? reqN.split('_').first : reqN;

      // 1. exact
      for (final l in available) {
        if (norm(l.localeId) == reqN) return l.localeId;
      }
      // 2. same language
      for (final l in available) {
        if (norm(l.localeId).startsWith('${reqLang}_')) return l.localeId;
      }
      // 3. bare language tag
      for (final l in available) {
        if (norm(l.localeId) == reqLang) return l.localeId;
      }
      // 4. system locale
      final system = await _engine.systemLocale();
      if (system != null) return system.localeId;
      // 5. first available
      return available.first.localeId;
    } catch (e) {
      debugPrint('VoiceService._resolveLocale error: $e — using $requested');
      return requested;
    }
  }

  @override
  Future<VoiceSessionResult> stop() async {
    // If VAD / the engine already resolved the session (common path — the UI
    // polls `isListening` and calls stop() afterwards), hand back the stored
    // result instead of a synthetic `cancelled/empty` one. That was the bug
    // that dropped the transcript on happy-path dictation.
    final stored = _lastResult;
    if (stored != null && _sessionCompleter == null) {
      return stored;
    }

    final completer = _sessionCompleter;
    if (completer == null) {
      return const VoiceSessionResult(
        status: VoiceSessionStatus.cancelled,
        transcript: '',
      );
    }

    _cancelledByCaller = true;
    if (_engine.isListening) {
      await _engine.stop();
    }
    if (!completer.isCompleted) {
      _complete(
        VoiceSessionResult(
          status: VoiceSessionStatus.cancelled,
          transcript: _lastTranscript,
        ),
      );
    }
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    if (_engine.isListening) {
      await _engine.cancel();
    }
    await _partialsCtrl?.close();
    _partialsCtrl = null;
    _sessionCompleter = null;
    _engineInitialized = false;
  }

  void _onEngineResult(SpeechRecognitionResult result) {
    _lastTranscript = result.recognizedWords;
    if (kDebugMode) {
      debugPrint(
        'VoiceService.onResult final=${result.finalResult} '
        'words="$_lastTranscript"',
      );
    }
    _partialsCtrl?.add(_lastTranscript);

    if (result.finalResult) {
      _complete(
        VoiceSessionResult(
          status: VoiceSessionStatus.completed,
          transcript: _lastTranscript,
        ),
      );
    }
  }

  void _onEngineStatus(String status) {
    if (kDebugMode) {
      debugPrint('VoiceService.status: $status');
    }
    // `speech_to_text` emits "done"/"notListening" when VAD auto-stops.
    // If we never received a final result (empty/noisy input), resolve now.
    if (status == stt.SpeechToText.doneStatus) {
      final completer = _sessionCompleter;
      if (completer != null && !completer.isCompleted) {
        _complete(
          VoiceSessionResult(
            status: _cancelledByCaller
                ? VoiceSessionStatus.cancelled
                : VoiceSessionStatus.completed,
            transcript: _lastTranscript,
          ),
        );
      }
    }
  }

  void _onEngineError(SpeechRecognitionError error) {
    final message = _mapErrorMessage(error);
    _complete(
      VoiceSessionResult(
        status: VoiceSessionStatus.error,
        transcript: _lastTranscript,
        errorMessage: message,
      ),
    );
  }

  void _complete(VoiceSessionResult result) {
    _lastResult = result;
    final completer = _sessionCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
    _partialsCtrl?.close();
    _partialsCtrl = null;
    _sessionCompleter = null;
  }

  String _mapErrorMessage(SpeechRecognitionError error) {
    // speech_to_text emits error codes like error_network, error_no_match,
    // error_speech_timeout, error_audio, etc. Network errors are the main
    // one we surface separately; everything else collapses to a generic msg.
    final code = error.errorMsg;
    if (code.contains('network')) {
      return 'requires internet';
    }
    return code;
  }
}
