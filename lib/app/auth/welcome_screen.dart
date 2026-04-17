import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:wallex/app/layout/page_switcher.dart';
import 'package:wallex/core/database/app_db.dart';
import 'package:wallex/core/database/services/app-data/app_data_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/database/utils/personal_ve_seeders.dart';
import 'package:wallex/core/services/firebase_sync_service.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:wallex/core/utils/unique_app_widgets_keys.dart';

/// First-run welcome screen. Offers two paths:
/// 1. "Iniciar con Google" (primary) — signs in, pulls Firebase data, seeds if empty.
/// 2. "Continuar sin cuenta" (secondary) — fully local, no auth required.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _continueWithoutAccount() async {
    // Ask whether to preload personal VE accounts & categories
    final shouldSeed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Precargar tus cuentas?'),
        content: const Text(
          'Wallex puede crear automaticamente tus cuentas bancarias '
          '(BDV, BNC, Banplus, Provincial, Binance, Zinli, etc.), '
          'categorias de ingreso/gasto y tags utiles.\n\n'
          'Puedes editarlos o eliminarlos despues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No, empezar vacio'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Si, precargar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      if (shouldSeed == true) {
        Logger.printDebug('WelcomeScreen: user accepted personal VE seed');
        // Show loading overlay while seeding (fire-and-forget; popped below)
        unawaited(showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator()),
        ));

        try {
          await PersonalVESeeder.seedAll();
        } catch (e) {
          Logger.printDebug('WelcomeScreen: seeding error: $e');
        }

        if (mounted) {
          Navigator.of(context).pop(); // dismiss loading overlay
        }
      }

      // Mark onboarding as completed
      await AppDataService.instance.setItem(
        AppDataKey.onboarded,
        '1',
        updateGlobalState: true,
      );
      await AppDataService.instance.setItem(
        AppDataKey.introSeen,
        '1',
        updateGlobalState: true,
      );

      Logger.printDebug('WelcomeScreen: continuing without account');

      if (mounted) {
        // Navigate to the main page, replacing the current route
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => PageSwitcher(key: tabsPageKey),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      Logger.printDebug('WelcomeScreen: error continuing without account: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      Logger.printDebug('WelcomeScreen: Google Sign-In successful');

      final user = FirebaseAuth.instance.currentUser;

      // Save user to local SQLite database
      if (user != null) {
        final db = AppDB.instance;
        await db.customStatement('''
          INSERT OR REPLACE INTO users (id, email, displayName, role, createdAt, lastLogin)
          VALUES (
            '${user.uid}',
            '${user.email ?? ''}',
            '${(user.displayName ?? '').replaceAll("'", "''")}',
            'user',
            datetime('now'),
            datetime('now')
          )
        ''');
      }

      // Enable sync + mark onboarded
      await FirebaseSyncService.instance.setSyncEnabled(true);
      await AppDataService.instance.setItem(
        AppDataKey.onboarded, '1', updateGlobalState: true,
      );
      await AppDataService.instance.setItem(
        AppDataKey.introSeen, '1', updateGlobalState: true,
      );

      if (user?.displayName != null) {
        await UserSettingService.instance.setItem(
          SettingKey.userName, user!.displayName, updateGlobalState: true,
        );
      }

      // --- Pull Firebase data → conditional seed → push ---
      Logger.printDebug('WelcomeScreen: pulling Firebase data...');
      final pullResult = await FirebaseSyncService.instance.pullAllData();
      final pulledAccounts = (pullResult['accounts'] as int?) ?? 0;

      if (pulledAccounts > 0) {
        Logger.printDebug(
          'WelcomeScreen: $pulledAccounts accounts restored from Firebase',
        );
      } else {
        // Firebase was empty — seed locally then push to Firebase
        final email = user?.email ?? '';
        Logger.printDebug(
          'WelcomeScreen: Firebase empty, seeding (email=$email)',
        );

        if (email == 'ramsesdavidba@gmail.com') {
          await PersonalVESeeder.seedAllWithBalances();
        } else {
          await PersonalVESeeder.seedAll();
        }

        Logger.printDebug('WelcomeScreen: pushing seeded data to Firebase...');
        await FirebaseSyncService.instance.pushAllData();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bienvenido!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => PageSwitcher(key: tabsPageKey),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      Logger.printDebug('WelcomeScreen: Google Sign-In error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al iniciar con Google: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          // Background decorations
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.secondary.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.secondary.withValues(alpha: 0.12),
                    blurRadius: 80,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // Logo / Icon
                  Icon(
                    Icons.account_balance_wallet,
                    size: 80,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Wallex',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Finanzas personales multi-moneda',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Error message
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error,
                              color: colorScheme.onErrorContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
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
                  ],

                  // Primary CTA: Sign in with Google
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _signInWithGoogle,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: colorScheme.onPrimary,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.login, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Iniciar con Google',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Secondary CTA: Continue without account
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _continueWithoutAccount,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'Continuar sin cuenta',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
