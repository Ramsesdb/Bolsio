import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';

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

    // Respect user toggle — skip auth entirely if disabled.
    final biometricEnabled = appStateSettings[SettingKey.biometricEnabled];
    if (biometricEnabled == '0') {
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
        localizedReason: 'Desbloquea Bolsio para acceder a tus finanzas',
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App icon
                Icon(
                  Icons.account_balance_wallet,
                  size: 80,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),

                // App name
                Text(
                  'Bolsio',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Toca para desbloquear',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),

                // Lock icon / fingerprint indicator
                if (_isAuthenticating)
                  SizedBox(
                    height: 48,
                    width: 48,
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                      strokeWidth: 3,
                    ),
                  )
                else
                  IconButton(
                    onPressed: _authenticate,
                    iconSize: 56,
                    color: colorScheme.primary,
                    icon: const Icon(Icons.fingerprint),
                  ),

                const SizedBox(height: 24),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: colorScheme.onErrorContainer,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
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
                    child: const Text('Reintentar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
