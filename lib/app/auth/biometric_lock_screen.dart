import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:nitido/app/onboarding/theme/v3_tokens.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/presentation/widgets/nitido_animated_logo.dart';

/// Full-screen biometric lock gate shown on app launch.
///
/// Behavior:
/// - Automatically triggers biometric prompt on load.
/// - Falls back to device PIN/pattern/password if biometrics aren't enrolled.
/// - If the device has NO security at all, calls [onAuthenticated] immediately.
/// - Shows a retry button on failure.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, required this.onAuthenticated});

  /// Called once the user successfully authenticates (or device has no security).
  final VoidCallback onAuthenticated;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  static const Color _bgTop = Color(0xFF0D0D1A);
  static const Color _bgBottom = Color(0xFF1A1A2E);
  static const Color _teal = V3Tokens.accent;
  static const Color _tealGlow = Color(0x4000897B);
  static const Color _tealFill = Color(0x1A00897B);
  static const Color _errorBg = Color(0x33EF4444);
  static const Color _errorBorder = Color(0x66EF4444);
  static const Color _errorIcon = Color(0xFFEF4444);
  static const Color _errorText = Color(0xFFFCA5A5);

  final LocalAuthentication _auth = LocalAuthentication();

  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Delay slightly so the UI renders before the system dialog appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    // Opt-in: only run the lock if the user explicitly enabled it ('1').
    // A null/missing value (fresh install) means the user has never turned it
    // on, so we skip the prompt entirely.
    final biometricEnabled = appStateSettings[SettingKey.biometricEnabled];
    if (biometricEnabled != '1') {
      widget.onAuthenticated();
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      // Check if the device supports any form of security.
      final isDeviceSupported = await _auth.isDeviceSupported();
      final canCheckBiometrics = await _auth.canCheckBiometrics;

      if (!isDeviceSupported && !canCheckBiometrics) {
        // Device has NO lock screen at all -- let the user through.
        widget.onAuthenticated();
        return;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: 'Desbloquea Nitido para acceder a tus finanzas',
        options: const AuthenticationOptions(
          // Allow PIN/pattern/password as fallback.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        widget.onAuthenticated();
      } else {
        setState(() {
          _errorMessage = 'Autenticacion cancelada';
          _isAuthenticating = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _bgBottom,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bgTop,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const NitidoAnimatedLogo(
                      showIcon: true,
                      fontSize: 40,
                      iconSize: 96,
                      subtitle: 'Toca para desbloquear',
                      animateIn: false,
                    ),
                    const SizedBox(height: 48),
                    if (_isAuthenticating)
                      const SizedBox(
                        height: 56,
                        width: 56,
                        child: CircularProgressIndicator(
                          color: _teal,
                          strokeWidth: 3,
                        ),
                      )
                    else
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _authenticate,
                          borderRadius: BorderRadius.circular(44),
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _tealFill,
                              border: Border.all(color: _teal, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: _tealGlow,
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.fingerprint,
                              size: 48,
                              color: _teal,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _errorBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _errorBorder, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: _errorIcon,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: _errorText,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _authenticate,
                        child: const Text(
                          'Reintentar',
                          style: TextStyle(
                            color: _teal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
