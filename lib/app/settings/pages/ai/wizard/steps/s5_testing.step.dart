import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kilatex/app/onboarding/theme/v3_tokens.dart';
import 'package:kilatex/app/settings/pages/ai/wizard/widgets/wizard_scaffold.dart';
import 'package:kilatex/core/services/ai/ai_credentials.dart';
import 'package:kilatex/core/services/ai/ai_service.dart';

/// Step 5 — runs `AiService.testCredentials` against the credentials the
/// user just typed in step 4.
///
/// States:
/// - `_TestState.running` → spinner + "Probando tu API key..."
/// - `_TestState.success` → check + "Conexión exitosa", auto-advance after
///   1.2s.
/// - `_TestState.failure` → cross + error message, two CTAs: Reintentar /
///   Editar key.
///
/// The test is hard-bounded to 10 seconds via `Future.timeout` so a hung
/// network never traps the user on the spinner.
enum _TestState { running, success, failure }

class S5TestingStep extends StatefulWidget {
  const S5TestingStep({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.credentials,
    required this.onSuccess,
    required this.onEditKey,
  });

  final int currentStep;
  final int totalSteps;
  final AiCredentials credentials;

  /// Called when the connection test passes. The wizard host is responsible
  /// for actually persisting the credentials (the test step never writes
  /// to the credentials store — that belongs to step 6 via the host).
  final VoidCallback onSuccess;

  /// Called when the user hits "Editar key" after a failure.
  final VoidCallback onEditKey;

  @override
  State<S5TestingStep> createState() => _S5TestingStepState();
}

class _S5TestingStepState extends State<S5TestingStep> {
  _TestState _state = _TestState.running;
  String? _errorMessage;
  Timer? _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();
    _runTest();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  Future<void> _runTest() async {
    setState(() {
      _state = _TestState.running;
      _errorMessage = null;
    });
    String? result;
    try {
      result = await AiService.instance
          .testCredentials(widget.credentials)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      result = 'La conexión tardó más de 10 segundos. Probá de nuevo.';
    } catch (e) {
      result = 'Error inesperado: $e';
    }
    if (!mounted) return;
    if (result == null) {
      setState(() => _state = _TestState.success);
      // Auto-advance after a short pause so the user can see the success
      // affirmation before we navigate.
      _autoAdvanceTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) widget.onSuccess();
      });
    } else {
      setState(() {
        _state = _TestState.failure;
        _errorMessage = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return WizardScaffold(
      currentStep: widget.currentStep,
      totalSteps: widget.totalSteps,
      // Hide the back pill while running — the user shouldn't be able to
      // pop mid-request and leave the test orphaned. Re-enable on failure.
      showBack: _state == _TestState.failure,
      onBack: widget.onEditKey,
      hideActions: _state != _TestState.failure,
      primaryLabel: 'Reintentar',
      onPrimary: _runTest,
      secondaryLabel: 'Editar key',
      onSecondary: widget.onEditKey,
      secondaryLeadingIcon: Icons.edit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: V3Tokens.space24),
          _StatusIcon(state: _state),
          const SizedBox(height: V3Tokens.space24),
          Text(
            _titleForState(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: V3Tokens.spaceMd),
          Text(
            _bodyForState(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
          if (_state == _TestState.failure && _errorMessage != null) ...[
            const SizedBox(height: V3Tokens.space24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(V3Tokens.space16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: V3Tokens.spaceMd),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: V3Tokens.uiStyle(
                        size: 13,
                        weight: FontWeight.w500,
                        color: scheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _titleForState() {
    switch (_state) {
      case _TestState.running:
        return 'Probando tu API key...';
      case _TestState.success:
        return 'Conexión exitosa';
      case _TestState.failure:
        return 'No pudimos conectar';
    }
  }

  String _bodyForState() {
    switch (_state) {
      case _TestState.running:
        return 'Estamos enviando un ping al proveedor para verificar que la key funciona. Esto consume ~10 tokens de tu cuota.';
      case _TestState.success:
        return 'Tu key está activa. En un momento te llevamos al final del setup.';
      case _TestState.failure:
        return 'Revisá la key y volvé a intentar. Si el problema persiste, asegurate de que el modelo elegido esté disponible para tu cuenta.';
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.state});
  final _TestState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _TestState.running:
        return const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            valueColor: AlwaysStoppedAnimation<Color>(V3Tokens.accent),
          ),
        );
      case _TestState.success:
        return Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: V3Tokens.accent,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.check_rounded,
            size: 36,
            color: Color(0xFF0A0A0A),
          ),
        );
      case _TestState.failure:
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red.withValues(alpha: 0.15),
            border: Border.all(color: Colors.red, width: 2),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.close_rounded,
            size: 36,
            color: Colors.red,
          ),
        );
    }
  }
}
