import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:kilatex/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:kilatex/core/presentation/widgets/modal_container.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';

/// The four flows the PIN modal supports. Each one is visually identical
/// (dots + keypad) but differs in how many steps it walks through and what it
/// calls on [HiddenModeService] when the user finishes.
enum PinModalMode {
  /// Create a brand-new PIN. Two steps: enter + confirm.
  setup,

  /// Validate the current PIN to transition Hidden Mode into the unlocked
  /// state. Also exposes the biometric shortcut when the OS supports it.
  unlock,

  /// Replace the current PIN. Three steps: old -> new -> confirm new.
  change,

  /// Validate the current PIN before disabling Hidden Mode entirely. The
  /// modal does NOT call [HiddenModeService.disableHiddenMode] itself — it
  /// returns the validated PIN to the caller so the caller can decide when
  /// to tear down the feature.
  confirmDisable,
}

// ────────────────────────────────────────────────────────────────────────────
//   Public API
// ────────────────────────────────────────────────────────────────────────────

/// Generic entry point. Return type depends on [mode]:
///
/// - [PinModalMode.setup] → `String?` (the new PIN if confirmed, `null` if
///   the user dismissed the sheet).
/// - [PinModalMode.unlock] → `bool` (`true` if unlocked, `false` if
///   dismissed).
/// - [PinModalMode.change] → `bool` (`true` if changed, `false` if
///   dismissed).
/// - [PinModalMode.confirmDisable] → `String?` (the validated PIN if the
///   user confirmed — pass it straight to
///   [HiddenModeService.disableHiddenMode] — or `null` if dismissed).
///
/// The typed variants below ([showSetupPinModal], [showUnlockPinModal], etc.)
/// are thin wrappers that let callers avoid dynamic typing.
Future<dynamic> showPinModal(
  BuildContext context, {
  required PinModalMode mode,
}) {
  switch (mode) {
    case PinModalMode.setup:
      return showSetupPinModal(context);
    case PinModalMode.unlock:
      return showUnlockPinModal(context);
    case PinModalMode.change:
      return showChangePinModal(context);
    case PinModalMode.confirmDisable:
      return showConfirmDisableModal(context);
  }
}

/// Setup flow: prompts the user to enter a PIN twice. Returns the created
/// PIN on success, `null` if the sheet was dismissed.
///
/// A successful confirmation internally calls
/// [HiddenModeService.setPin] before returning.
Future<String?> showSetupPinModal(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const PinModal(mode: PinModalMode.setup),
  );
}

/// Unlock flow: validates the PIN and, on success, flips
/// [HiddenModeService] into the unlocked state before returning `true`.
/// Also exposes a biometric shortcut when the platform supports it.
Future<bool> showUnlockPinModal(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const PinModal(mode: PinModalMode.unlock),
  );
  return result ?? false;
}

/// Change-PIN flow: validates the current PIN, asks for a new one twice and
/// calls [HiddenModeService.changePin] on success. Returns `true` if the PIN
/// was rotated.
Future<bool> showChangePinModal(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const PinModal(mode: PinModalMode.change),
  );
  return result ?? false;
}

/// Disable-confirmation flow: validates the current PIN and returns it so
/// the caller can invoke [HiddenModeService.disableHiddenMode] (which itself
/// re-validates before mutating state). Returns `null` if dismissed.
Future<String?> showConfirmDisableModal(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const PinModal(mode: PinModalMode.confirmDisable),
  );
}

// ────────────────────────────────────────────────────────────────────────────
//   Implementation
// ────────────────────────────────────────────────────────────────────────────

/// Length of every PIN in every flow. Kept as a constant so tests can depend
/// on it without hard-coding 6 in each expectation.
const int kPinLength = 6;

/// Max consecutive wrong PIN attempts before the keypad locks out.
const int kMaxAttempts = 5;

/// How long the keypad stays disabled after hitting [kMaxAttempts].
const Duration kCooldown = Duration(seconds: 30);

/// Low-level PIN modal widget. Normally callers use the top-level
/// `showXxxPinModal` helpers, but the class is exposed publicly so widget
/// tests can pump it inside a `Scaffold` without booting a full bottom
/// sheet.
class PinModal extends StatefulWidget {
  const PinModal({super.key, required this.mode, this.serviceOverride});

  final PinModalMode mode;

  /// Optional injected service for widget tests. When `null` (production
  /// path) the modal talks to [HiddenModeService.instance]. Tests pass a
  /// [HiddenModeService.forTesting] instance to avoid booting Drift +
  /// secure storage plugin channels.
  @visibleForTesting
  final HiddenModeService? serviceOverride;

  @override
  State<PinModal> createState() => PinModalState();
}

/// Internal step machine. Each mode uses a subset of these steps — the state
/// class decides which one is active at any moment and uses it to pick the
/// title + the handler to run when 6 digits land.
enum _Step {
  enter, // generic "enter PIN" (unlock / disable / first setup entry)
  confirm, // confirm a freshly entered PIN (setup)
  changeOld, // current PIN (change)
  changeNew, // new PIN (change, step 2)
  changeConfirm, // confirm new PIN (change, step 3)
}

@visibleForTesting
class PinModalState extends State<PinModal>
    with SingleTickerProviderStateMixin {
  late _Step _step = _initialStep(widget.mode);

  /// Current buffer of digits the user has entered in the active step.
  String _current = '';

  /// First PIN captured during setup or change (pending confirmation).
  String? _firstPin;

  /// Validated "old PIN" used in the change flow to feed
  /// [HiddenModeService.changePin] at the end.
  String? _oldPin;

  /// User-facing error message. Cleared on the next keystroke.
  String? _error;

  /// Consecutive failed attempts. Resets on a successful step advance.
  int _failedAttempts = 0;

  /// Countdown seconds while the keypad is cooling down; `null` when the
  /// keypad is active.
  int? _cooldownSeconds;
  Timer? _cooldownTimer;

  /// Whether an async validation is in flight. Used to block double taps on
  /// the last digit and to dim the UI.
  bool _validating = false;

  /// Whether biometric auth is available on this device. Queried lazily on
  /// `initState` for unlock mode only.
  bool _biometricAvailable = false;

  /// Animation driver for the shake-on-error effect.
  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  HiddenModeService get _service =>
      widget.serviceOverride ?? HiddenModeService.instance;

  // ─── Testing hooks ───
  @visibleForTesting
  String get currentBuffer => _current;
  @visibleForTesting
  int get failedAttempts => _failedAttempts;
  @visibleForTesting
  bool get keypadDisabled => _isKeypadDisabled;
  @visibleForTesting
  int? get cooldownSeconds => _cooldownSeconds;

  static _Step _initialStep(PinModalMode mode) {
    switch (mode) {
      case PinModalMode.setup:
      case PinModalMode.unlock:
      case PinModalMode.confirmDisable:
        return _Step.enter;
      case PinModalMode.change:
        return _Step.changeOld;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.mode == PinModalMode.unlock) {
      _queryBiometricAvailability();
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _queryBiometricAvailability() async {
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      if (!mounted) return;
      setState(() => _biometricAvailable = supported && canCheck);
    } catch (_) {
      // If the platform channel throws (e.g. host app didn't enable the
      // plugin, running on an unsupported desktop build), silently hide the
      // biometric button.
    }
  }

  // ─────────── Keypad handlers ───────────

  bool get _isKeypadDisabled => _cooldownSeconds != null || _validating;

  void _onDigit(String digit) {
    if (_isKeypadDisabled) return;
    if (_current.length >= kPinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _current = '$_current$digit';
      _error = null;
    });
    if (_current.length == kPinLength) {
      _submit();
    }
  }

  void _onBackspace() {
    if (_isKeypadDisabled) return;
    if (_current.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _current = _current.substring(0, _current.length - 1);
      _error = null;
    });
  }

  /// Called when the buffer reaches [kPinLength]. Dispatches on the current
  /// step and triggers the matching service call.
  Future<void> _submit() async {
    final entered = _current;
    setState(() => _validating = true);
    try {
      switch (_step) {
        case _Step.enter:
          await _handleEnter(entered);
          break;
        case _Step.confirm:
          await _handleConfirm(entered);
          break;
        case _Step.changeOld:
          await _handleChangeOld(entered);
          break;
        case _Step.changeNew:
          _handleChangeNew(entered);
          break;
        case _Step.changeConfirm:
          await _handleChangeConfirm(entered);
          break;
      }
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Future<void> _handleEnter(String pin) async {
    switch (widget.mode) {
      case PinModalMode.setup:
        // First entry captured — move on to the confirmation step.
        _firstPin = pin;
        _failedAttempts = 0;
        setState(() {
          _step = _Step.confirm;
          _current = '';
        });
        return;

      case PinModalMode.unlock:
        final ok = await _service.unlock(pin);
        if (!mounted) return;
        if (ok) {
          Navigator.of(context).pop(true);
        } else {
          _registerFailedAttempt(_t(context).incorrect);
        }
        return;

      case PinModalMode.confirmDisable:
        final ok = await _service.validatePin(pin);
        if (!mounted) return;
        if (ok) {
          Navigator.of(context).pop(pin);
        } else {
          _registerFailedAttempt(_t(context).incorrect);
        }
        return;

      case PinModalMode.change:
        // Unreachable: change mode never uses _Step.enter.
        return;
    }
  }

  Future<void> _handleConfirm(String pin) async {
    if (pin != _firstPin) {
      _firstPin = null;
      _shake();
      setState(() {
        _error = _t(context).mismatch;
        _current = '';
        _step = _Step.enter;
      });
      return;
    }
    await _service.setPin(pin);
    if (!mounted) return;
    Navigator.of(context).pop(pin);
  }

  Future<void> _handleChangeOld(String pin) async {
    final ok = await _service.validatePin(pin);
    if (!mounted) return;
    if (!ok) {
      _registerFailedAttempt(_t(context).incorrect);
      return;
    }
    _oldPin = pin;
    _failedAttempts = 0;
    setState(() {
      _step = _Step.changeNew;
      _current = '';
    });
  }

  void _handleChangeNew(String pin) {
    _firstPin = pin;
    setState(() {
      _step = _Step.changeConfirm;
      _current = '';
    });
  }

  Future<void> _handleChangeConfirm(String pin) async {
    if (pin != _firstPin) {
      _firstPin = null;
      _shake();
      setState(() {
        _error = _t(context).mismatch;
        _current = '';
        _step = _Step.changeNew;
      });
      return;
    }
    try {
      await _service.changePin(_oldPin!, pin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on StateError {
      // The old PIN was valid a moment ago; if changePin rejects it we
      // probably hit a race with another caller rotating the PIN. Surface as
      // a generic "incorrect" error and send the user back to step 1.
      _oldPin = null;
      _firstPin = null;
      _shake();
      setState(() {
        _error = _t(context).incorrect;
        _current = '';
        _step = _Step.changeOld;
      });
    }
  }

  void _registerFailedAttempt(String message) {
    _failedAttempts += 1;
    _shake();
    if (_failedAttempts >= kMaxAttempts) {
      _startCooldown();
      return;
    }
    setState(() {
      _error = message;
      _current = '';
    });
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownSeconds = kCooldown.inSeconds;
      _current = '';
      _error = _t(context).too_many_attempts(seconds: kCooldown.inSeconds);
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = (_cooldownSeconds ?? 1) - 1;
      if (next <= 0) {
        timer.cancel();
        setState(() {
          _cooldownSeconds = null;
          _failedAttempts = 0;
          _error = null;
        });
      } else {
        setState(() {
          _cooldownSeconds = next;
          _error = _t(context).too_many_attempts(seconds: next);
        });
      }
    });
  }

  void _shake() {
    _shakeController.forward(from: 0).then((_) {
      if (mounted) _shakeController.reset();
    });
  }

  // ─────────── Biometric shortcut ───────────

  Future<void> _tryBiometric() async {
    if (_isKeypadDisabled) return;
    try {
      final auth = LocalAuthentication();
      final ok = await auth.authenticate(
        localizedReason: _t(context).biometric_reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!ok || !mounted) return;
      _service.unlockWithBiometric();
      Navigator.of(context).pop(true);
    } catch (_) {
      // Swallow: the OS already surfaces its own error dialog, and the user
      // can still fall back to the PIN keypad.
    }
  }

  // ─────────── Build ───────────

  /// All locales' `pin` classes extend the English one, so the base type is
  /// safe to use as a shared interface.
  TranslationsSettingsHiddenModePinEn _t(BuildContext context) {
    return Translations.of(context).settings.hidden_mode.pin;
  }

  String _titleForStep(BuildContext context) {
    final t = _t(context);
    switch (_step) {
      case _Step.enter:
        switch (widget.mode) {
          case PinModalMode.setup:
            return t.setup_title;
          case PinModalMode.unlock:
            return t.unlock_title;
          case PinModalMode.confirmDisable:
            return t.disable_title;
          case PinModalMode.change:
            return t.change_old_title;
        }
      case _Step.confirm:
        return t.confirm_title;
      case _Step.changeOld:
        return t.change_old_title;
      case _Step.changeNew:
        return t.change_new_title;
      case _Step.changeConfirm:
        return t.change_confirm_title;
    }
  }

  String? _subtitleForStep() {
    if (_step == _Step.enter && widget.mode == PinModalMode.setup) {
      return _t(context).setup_subtitle;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ModalContainer(
      title: _titleForStep(context),
      subtitle: _subtitleForStep(),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                // Damped sine wave — oscillates ±10px twice while decaying
                // back to 0 over the animation's duration.
                final t = _shakeController.value;
                final dx =
                    t == 0 ? 0.0 : 10 * (1 - t) * math.sin(t * math.pi * 4);
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: child,
                );
              },
              child: _PinDots(
                length: kPinLength,
                filled: _current.length,
                hasError: _error != null,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 22,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _error == null
                    ? const SizedBox.shrink()
                    : Text(
                        _error!,
                        key: const ValueKey('pin-error'),
                        style: TextStyle(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _Keypad(
              disabled: _isKeypadDisabled,
              onDigit: _onDigit,
              onBackspace: _onBackspace,
              showBiometric:
                  widget.mode == PinModalMode.unlock && _biometricAvailable,
              onBiometric: _tryBiometric,
              biometricTooltip: _t(context).use_biometric,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────── Child widgets ───────────

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filled,
    required this.hasError,
  });

  final int length;
  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = hasError ? colorScheme.error : colorScheme.primary;
    final inactiveColor = colorScheme.onSurface.withValues(alpha: 0.18);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? activeColor : Colors.transparent,
              border: Border.all(
                color: isFilled ? activeColor : inactiveColor,
                width: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.disabled,
    required this.onDigit,
    required this.onBackspace,
    required this.showBiometric,
    required this.onBiometric,
    required this.biometricTooltip,
  });

  final bool disabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool showBiometric;
  final VoidCallback onBiometric;
  final String biometricTooltip;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: IgnorePointer(
        ignoring: disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final d in row)
                    _KeypadButton(label: d, onTap: () => onDigit(d)),
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: showBiometric
                      ? _KeypadIconButton(
                          key: const ValueKey('pin-biometric'),
                          icon: Icons.fingerprint,
                          tooltip: biometricTooltip,
                          onTap: onBiometric,
                        )
                      : const SizedBox.shrink(),
                ),
                _KeypadButton(label: '0', onTap: () => onDigit('0')),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: _KeypadIconButton(
                    key: const ValueKey('pin-backspace'),
                    icon: Icons.backspace_outlined,
                    tooltip: 'Backspace',
                    onTap: onBackspace,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: const CircleBorder(),
          child: InkWell(
            key: ValueKey('pin-key-$label'),
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeypadIconButton extends StatelessWidget {
  const _KeypadIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: Icon(icon, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
