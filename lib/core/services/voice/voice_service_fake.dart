import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:kilatex/core/services/voice/voice_service.dart';

/// Test fake for [VoiceService]. Emits a canned sequence of partials, then
/// resolves [stop] with a final transcript.
///
/// Used by unit/widget tests across Tandas 4–5 to drive the mic UX without
/// touching the real `speech_to_text` plugin.
class FakeVoiceService implements VoiceService {
  FakeVoiceService({
    this.cannedPartials = const ['gasté', 'gasté veinte'],
    this.cannedFinal = 'gasté veinte dólares en almuerzo',
    this.permissionStatus = PermissionStatus.granted,
    this.errorMessage,
    this.partialDelay = const Duration(milliseconds: 120),
  });

  final List<String> cannedPartials;
  final String cannedFinal;
  final PermissionStatus permissionStatus;

  /// When set, the session resolves with [VoiceSessionStatus.error] on stop.
  final String? errorMessage;
  final Duration partialDelay;

  StreamController<String>? _ctrl;
  String _last = '';
  bool _active = false;
  Timer? _emitTimer;
  int _emitIndex = 0;

  @override
  Stream<String> get partials =>
      _ctrl?.stream ?? const Stream<String>.empty();

  @override
  bool get isListening => _active;

  @override
  Future<PermissionStatus> ensurePermission() async => permissionStatus;

  @override
  Future<void> startSession({
    String locale = 'es_VE',
    Duration maxDuration = const Duration(seconds: 30),
  }) async {
    if (_active) {
      throw StateError('FakeVoiceService: already listening');
    }
    _active = true;
    _last = '';
    _emitIndex = 0;
    _ctrl = StreamController<String>.broadcast();

    void tick(Timer _) {
      if (!_active || _ctrl == null) return;
      if (_emitIndex >= cannedPartials.length) {
        _emitTimer?.cancel();
        return;
      }
      _last = cannedPartials[_emitIndex++];
      _ctrl!.add(_last);
    }

    _emitTimer = Timer.periodic(partialDelay, tick);
  }

  @override
  Future<VoiceSessionResult> stop() async {
    _emitTimer?.cancel();
    _emitTimer = null;
    if (!_active) {
      return const VoiceSessionResult(
        status: VoiceSessionStatus.cancelled,
        transcript: '',
      );
    }
    _active = false;

    final msg = errorMessage;
    final result = msg != null
        ? VoiceSessionResult(
            status: VoiceSessionStatus.error,
            transcript: _last,
            errorMessage: msg,
          )
        : VoiceSessionResult(
            status: VoiceSessionStatus.completed,
            transcript: cannedFinal,
          );

    await _ctrl?.close();
    _ctrl = null;
    return result;
  }

  @override
  Future<void> dispose() async {
    _emitTimer?.cancel();
    _emitTimer = null;
    _active = false;
    await _ctrl?.close();
    _ctrl = null;
  }
}
