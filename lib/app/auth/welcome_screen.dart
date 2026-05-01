import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nitido/app/auth/returning_user_flow.dart';
import 'package:nitido/app/onboarding/onboarding.dart';
import 'package:nitido/app/onboarding/theme/v3_tokens.dart';
import 'package:nitido/app/onboarding/widgets/v3_primary_button.dart';
import 'package:nitido/app/onboarding/widgets/v3_secondary_button.dart';
import 'package:nitido/core/database/app_db.dart';
import 'package:nitido/core/database/services/app-data/app_data_service.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/presentation/widgets/nitido_animated_logo.dart';
import 'package:nitido/core/services/firebase_sync_service.dart';
import 'package:nitido/core/utils/logger.dart';

/// First-run welcome screen. Offers two paths:
/// 1. "Iniciar con Google" (primary) — signs in, pulls Firebase data, seeds if empty.
/// 2. "Continuar sin cuenta" (secondary) — fully local, no auth required.
///
/// Both paths set `AppDataKey.onboarded = '1'` and then navigate to the
/// 10-slide [OnboardingPage]. The router (`InitialPageRouteNavigator` in
/// `lib/main.dart`) flips `AppDataKey.introSeen` only at the end of the
/// onboarding, so the intro is preserved on fresh installs.
///
/// Layout (v3 hero):
/// - Background: pure AMOLED black (#000000) on dark, #FAFAF7 on light.
/// - Top-left: small "Nitido" wordmark.
/// - Middle: large display title left-aligned ("Tu dinero en bolívares y
///   dólares, al día.") using Gabarito 900 (clamped to fit the viewport).
/// - Bottom: full-width primary + secondary pill buttons.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _continueWithoutAccount() async {
    // No pre-seed dialog: the v3 onboarding flow's slide 4 lets the user pick
    // their banks/wallets and slide 9 runs `PersonalVESeeder.seedAll` with
    // those selections. Pre-seeding here would create the always-on cash
    // accounts and trip the seeder's idempotency guard, silently dropping
    // every BankOption the user toggles in slide 4.
    setState(() => _isLoading = true);

    try {
      // Mark onboarding as completed (only `onboarded`; `introSeen` flips at
      // the end of the 10-slide OnboardingPage). Setting both here would skip
      // the intro entirely on fresh installs.
      await AppDataService.instance.setItem(
        AppDataKey.onboarded,
        '1',
        updateGlobalState: true,
      );

      Logger.printDebug('WelcomeScreen: continuing without account');

      if (mounted) {
        // Navigate to the 10-slide onboarding (NOT PageSwitcher) so users
        // still see the intro on first launch.
        await Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const OnboardingPage(),
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

      // Enable sync + mark onboarded (NOT introSeen — that flips at end of
      // OnboardingPage so users still see the 10-slide intro on fresh install).
      await FirebaseSyncService.instance.setSyncEnabled(true);
      await AppDataService.instance.setItem(
        AppDataKey.onboarded, '1', updateGlobalState: true,
      );

      if (user?.displayName != null) {
        await UserSettingService.instance.setItem(
          SettingKey.userName, user!.displayName, updateGlobalState: true,
        );
      }

      // --- Pull Firebase data → conditional seed → push ---
      // Stamp the pull timestamp BEFORE issuing the network request so the
      // post-frame pull guard in `InitialPageRouteNavigator` (main.dart) can
      // skip its duplicate `pullAllData()` when this welcome flow already
      // covered it. See Fix 2 (Opción A) in the auth flow notes.
      await AppDataService.instance.setItem(
        AppDataKey.lastPullAt,
        DateTime.now().millisecondsSinceEpoch.toString(),
        updateGlobalState: true,
      );

      Logger.printDebug('WelcomeScreen: pulling Firebase data...');
      final pullResult = await FirebaseSyncService.instance.pullAllData();
      final pulledAccounts = (pullResult['accounts'] as int?) ?? 0;

      // Returning user (data already in Firebase) → mini "welcome back" flow.
      // First-time Google user (Firebase empty) → continue with the full
      // 10-slide intro after seeding locally and pushing to Firebase.
      final bool isReturningUser = pulledAccounts > 0;

      if (isReturningUser) {
        Logger.printDebug(
          'WelcomeScreen: $pulledAccounts accounts restored from Firebase '
          '— routing to ReturningUserFlow',
        );
      } else {
        // Firebase was empty. The seeder must NOT run here: slide 9 of the v3
        // onboarding owns seeding and depends on the user's slide-4 bank
        // picks. Pre-seeding now would create the always-on cash accounts
        // and trip the seeder's idempotency guard, silently dropping every
        // BankOption the user toggles.
        //
        // Defer seeding to slide 9. Push will run on the next sync trigger
        // once the user reaches the home screen.
        Logger.printDebug(
          'WelcomeScreen: Firebase empty — deferring seed to onboarding slide 9',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bienvenido!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );

        if (isReturningUser) {
          // Skip the 10-slide onboarding — the user already knows the app.
          // Mini-flow: welcome back + activate listener (compact).
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => ReturningUserFlow(
                displayName: user?.displayName,
              ),
            ),
            (route) => false,
          );
        } else {
          // Navigate to the 10-slide onboarding (NOT PageSwitcher) so new
          // users still see the intro on first launch.
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const OnboardingPage(),
            ),
            (route) => false,
          );
        }
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
          // Decorative accent circle — kept for v3 brand continuity but
          // dimmed so the display copy stays the hero.
          Positioned(
            top: -120,
            right: -120,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: V3Tokens.accent.withValues(alpha: 0.10),
                boxShadow: const [
                  BoxShadow(
                    color: V3Tokens.pulseHalo,
                    blurRadius: 80,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Center(
                    child: NitidoAnimatedLogo(
                      showIcon: true,
                      subtitle: 'Tus cuentas, por fin claras.',
                      iconSize: 110,
                      fontSize: 44,
                      animateIn: true,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Error banner.
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(V3Tokens.spaceMd),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(V3Tokens.radiusMd),
                            border: Border.all(
                              color: colorScheme.error.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error,
                                  color: colorScheme.onErrorContainer, size: 20),
                              const SizedBox(width: V3Tokens.spaceXs),
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
                        const SizedBox(height: V3Tokens.space16),
                      ],

                      // Primary CTA — full width via stretch crossAxisAlignment.
                      V3PrimaryButton(
                        label: 'Iniciar con Google',
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        trailingIcon: Icons.arrow_forward,
                        loading: _isLoading,
                      ),
                      const SizedBox(height: V3Tokens.spaceMd),

                      // Secondary CTA.
                      V3SecondaryButton(
                        label: 'Continuar sin cuenta',
                        onPressed: _isLoading ? null : _continueWithoutAccount,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
