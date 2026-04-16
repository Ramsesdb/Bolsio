import 'dart:async' show unawaited;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:wallex/app/auth/biometric_lock_screen.dart';
import 'package:wallex/app/auth/welcome_screen.dart';
import 'package:wallex/app/layout/page_switcher.dart';
import 'package:wallex/app/layout/widgets/app_navigation_sidebar.dart';
import 'package:wallex/app/layout/window_bar.dart';
import 'package:wallex/app/onboarding/intro.page.dart';
import 'package:wallex/core/database/services/app-data/app_data_service.dart';
import 'package:wallex/core/database/services/user-setting/private_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/database/services/user-setting/utils/get_theme_from_string.dart';
import 'package:wallex/core/presentation/helpers/global_snackbar.dart';
import 'package:wallex/core/presentation/theme.dart';
import 'package:wallex/core/routes/handle_will_pop_scope.dart';
import 'package:wallex/core/routes/root_navigator_observer.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/firebase_sync_service.dart';
import 'package:wallex/core/utils/app_utils.dart';
import 'package:wallex/core/utils/keyboard_intents.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:wallex/core/utils/scroll_behavior_override.dart';
import 'package:wallex/core/utils/unique_app_widgets_keys.dart';
import 'package:wallex/i18n/generated/translations.g.dart';
import 'package:wallex/core/services/auto_import/background/local_notification_service.dart';
import 'package:wallex/core/services/auto_import/background/wallex_background_service.dart';
import 'package:wallex/core/services/auto_import/orchestrator/capture_orchestrator.dart';
import 'package:wallex/app/transactions/auto_import/pending_imports.page.dart';
import 'package:wallex/core/services/dolar_api_service.dart';
import 'package:wallex/core/services/rate_providers/rate_provider_manager.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/utils/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallex/core/database/app_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize settings first so we can check the sync flag
  await UserSettingService.instance.initializeGlobalStateMap();
  await AppDataService.instance.initializeGlobalStateMap();

  // Initialize Firebase ONLY if sync is enabled (opt-in)
  final syncEnabled = appStateSettings[SettingKey.firebaseSyncEnabled] == '1';
  if (syncEnabled) {
    try {
      await Firebase.initializeApp();
      await FirebaseSyncService.instance.initialize();
    } catch (e) {
      // Firebase init can fail on some devices - app should still work offline
      debugPrint('Firebase initialization failed: $e');
    }
  } else {
    debugPrint('Firebase sync disabled — skipping Firebase.initializeApp()');
  }

  // --- Auto-update Currency Rate (Daily) ---
  try {
    await _checkAndAutoUpdateCurrencyRate();
  } catch (e) {
    debugPrint('Error auto-updating currency rate: $e');
  }
  // -----------------------------------------

  // --- Local notifications bootstrap ---
  unawaited(
    LocalNotificationService.instance
        .initialize(
          onTap: (response) {
            // Navigate to PendingImportsPage when user taps the notification
            if (response.payload == 'pending_imports') {
              RouteUtils.pushRoute(const PendingImportsPage());
            }
          },
        )
        .catchError((e) {
          debugPrint('Local notification init error: $e');
        }),
  );
  // -----------------------------------------

  // --- Background service + Auto-import bootstrap ---
  final autoImportEnabled =
      appStateSettings[SettingKey.autoImportEnabled] == '1';

  // Initialize background service (configures but does not start)
  unawaited(
    WallexBackgroundService.instance.initialize().then((_) async {
      if (autoImportEnabled) {
        // Wire the orchestrator's callback so the main isolate can show
        // local notifications when a new pending import arrives.
        // NOTE: We do NOT call applySettings() here — the background
        // isolate's _onStart already starts the orchestrator.  Running it
        // in both isolates caused duplicate captures.
        CaptureOrchestrator.instance.onNewPendingImport =
            (int count) async {
          await LocalNotificationService.instance
              .showNewPendingNotification(count);
        };

        // Start the background service — it runs CaptureOrchestrator
        // independently so capture survives app close.
        await WallexBackgroundService.instance.startService();
      }
    }).catchError((e) {
      debugPrint('Auto-import bootstrap error: $e');
    }),
  );
  // ---------------------------------------------------

  PrivateModeService.instance.setPrivateMode(
    appStateSettings[SettingKey.privateModeAtLaunch] == '1',
  );

  // Set plural resolver for Turkish
  LocaleSettings.setPluralResolver(
    language: 'tr',
    cardinalResolver:
        (
          n, {
          String? few,
          String? many,
          String? one,
          String? other,
          String? two,
          String? zero,
        }) {
          if (n == 1) return 'one';
          return 'other';
        },
  );

  debugPaintSizeEnabled = false;
  runApp(InitializeApp(key: appStateKey));
}

// ignore: library_private_types_in_public_api
GlobalKey<_InitializeAppState> appStateKey = GlobalKey();

class InitializeApp extends StatefulWidget {
  const InitializeApp({super.key});

  @override
  State<InitializeApp> createState() => _InitializeAppState();
}

class _InitializeAppState extends State<InitializeApp> {
  bool _biometricPassed = false;

  void refreshAppState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_biometricPassed) {
      // Show biometric lock gate before any app content.
      // Uses a minimal MaterialApp so the lock screen has a theme.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: ThemeMode.system,
        home: BiometricLockScreen(
          onAuthenticated: () {
            setState(() => _biometricPassed = true);
          },
        ),
      );
    }

    // ignore: prefer_const_constructors
    return WallexAppEntryPoint(key: const ValueKey('App Entry Point'));
  }
}

class WallexAppEntryPoint extends StatelessWidget {
  const WallexAppEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    Logger.printDebug('------------------ APP ENTRY POINT ------------------');

    _setAppLanguage();

    return TranslationProvider(
      child: MaterialAppContainer(
        amoledMode: appStateSettings[SettingKey.amoledMode]! == '1',
        accentColor: appStateSettings[SettingKey.accentColor]!,
        themeMode: getThemeFromString(appStateSettings[SettingKey.themeMode]!),
      ),
    );
  }

  void _setAppLanguage() {
    final lang = appStateSettings[SettingKey.appLanguage];

    if (lang != null && lang.isNotEmpty) {
      Logger.printDebug(
        'App language found in DB. Setting the locale to `$lang`...',
      );
      LocaleSettings.setLocaleRaw(lang).then((setLocale) {
        if (setLocale.languageTag != lang) {
          Logger.printDebug(
            'Warning: The requested locale `$lang` is not available. Fallback to `${setLocale.languageTag}`.',
          );

          // Set auto as a language:
          UserSettingService.instance
              .setItem(SettingKey.appLanguage, null)
              .then((value) {});
        } else {
          Logger.printDebug('App language set with success');
        }
      });

      return;
    }

    Logger.printDebug(
      'App language not found in DB. Using device locale...',
    );

    // Uses locale of the device, fallbacks to base locale. Returns the locale which has been set:
    LocaleSettings.useDeviceLocale()
        .then((setLocale) {
          Logger.printDebug(
            'App language set to device language: ${setLocale.languageTag}',
          );
        })
        .catchError((error) {
          Logger.printDebug(
            'Error setting app language to device language: $error',
          );
        })
        .whenComplete(() {
          // The set locale should be accessible via LocaleSettings.currentLocale
          Logger.printDebug(
            'Current locale: ${LocaleSettings.currentLocale.languageTag}',
          );
        });
  }
}

class MaterialAppContainer extends StatelessWidget {
  const MaterialAppContainer({
    super.key,
    required this.themeMode,
    required this.accentColor,
    required this.amoledMode,
  });

  final ThemeMode themeMode;
  final String accentColor;
  final bool amoledMode;

  SystemUiOverlayStyle getSystemUiOverlayStyle(Brightness brightness) {
    if (brightness == Brightness.light) {
      return SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        systemStatusBarContrastEnforced: false,
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: kIsWeb ? Colors.black : Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      );
    } else {
      return SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        systemStatusBarContrastEnforced: false,
        statusBarIconBrightness: Brightness.light,
        statusBarColor: kIsWeb ? Colors.black : Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the language of the Intl in each rebuild of the TranslationProvider:
    Intl.defaultLocale = LocaleSettings.currentLocale.languageTag;

    final introSeen = appStateData[AppDataKey.introSeen] == '1';
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'Wallex',
          debugShowCheckedModeBanner: false,
          color: Theme.of(context).colorScheme.primary,
          shortcuts: appShortcuts,
          actions: keyboardIntents,
          locale: TranslationProvider.of(context).flutterLocale,
          scrollBehavior: ScrollBehaviorOverride(),
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          scaffoldMessengerKey: snackbarKey,
          theme: getThemeData(
            context,
            isDark: false,
            amoledMode: amoledMode,
            lightDynamic: lightDynamic,
            darkDynamic: darkDynamic,
            accentColor: accentColor,
          ),
          darkTheme: getThemeData(
            context,
            isDark: true,
            amoledMode: amoledMode,
            lightDynamic: lightDynamic,
            darkDynamic: darkDynamic,
            accentColor: accentColor,
          ),
          themeMode: themeMode,
          navigatorKey: rootNavigatorKey,
          navigatorObservers: [MainLayoutNavObserver()],
          builder: (context, child) {
            SystemChrome.setSystemUIOverlayStyle(
              getSystemUiOverlayStyle(Theme.of(context).brightness),
            );

            child ??= const SizedBox.shrink();

            return child;
          },
          home: HandleWillPopScope(
            child: Builder(
              builder: (context) {
                final mainSide = Stack(
                  children: [
                    InitialPageRouteNavigator(introSeen: introSeen),
                    GlobalSnackbar(key: globalSnackbarKey),
                  ],
                );

                final mainContent = ColoredBox(
                  color: getWindowBackgroundColor(context),
                  child: Row(
                    children: [
                      if (introSeen)
                        AppNavigationSidebar(key: navigationSidebarKey),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            if (AppUtils.isDesktop &&
                                !AppUtils.isMobileLayout(context)) {
                              return ClipRRect(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                ),
                                child: mainSide,
                              );
                            }

                            return mainSide;
                          },
                        ),
                      ),
                    ],
                  ),
                );

                if (!AppUtils.isDesktop) {
                  return mainContent;
                }

                return Column(
                  children: [
                    WindowBar(key: windowBarKey),
                    Expanded(child: mainContent),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Handles onboarding and optional authentication.
///
/// Flow:
/// 1. If not onboarded → WelcomeScreen (first run)
/// 2. If onboarded but introSeen is false → IntroPage (currency/category setup)
/// 3. Otherwise → PageSwitcher (main app)
///
/// Firebase sync is triggered in the background only when enabled + logged in.
class InitialPageRouteNavigator extends StatelessWidget {
  const InitialPageRouteNavigator({super.key, required this.introSeen});

  final bool introSeen;

  @override
  Widget build(BuildContext context) {
    final onboarded = appStateData[AppDataKey.onboarded] == '1';

    Logger.printDebug(
      'ROUTE STATE: onboarded=$onboarded, introSeen=$introSeen, '
      'syncAvailable=${FirebaseSyncService.instance.isFirebaseAvailable}',
    );

    // First run: show welcome screen
    if (!onboarded) {
      return HeroControllerScope(
        controller: MaterialApp.createMaterialHeroController(),
        child: Navigator(
          key: navigatorKey,
          onGenerateRoute: (settings) =>
              RouteUtils.getPageRouteBuilder(const WelcomeScreen()),
        ),
      );
    }

    // Trigger background sync if Firebase is available and user is logged in
    if (FirebaseSyncService.instance.isFirebaseAvailable) {
      FirebaseSyncService.instance.pullAllData();
    }

    return HeroControllerScope(
      controller: MaterialApp.createMaterialHeroController(),
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (settings) => RouteUtils.getPageRouteBuilder(
          introSeen
              ? PageSwitcher(key: tabsPageKey)
              : const IntroPage(),
        ),
      ),
    );
  }
}

/// Helper to auto-update currency rates (BCV + paralelo) once a day.
///
/// Fetches both sources via [RateProviderManager] (fallback chain) and stores
/// each one with its source tag. Also maintains backwards-compatible insertion
/// without source for existing callers.
Future<void> _checkAndAutoUpdateCurrencyRate() async {
  final prefs = await SharedPreferences.getInstance();
  final lastUpdateStr = prefs.getString('last_currency_auto_update_v3');
  final now = DateTime.now();

  // If updated less than 12h ago, skip
  if (lastUpdateStr != null) {
    final lastUpdate = DateTime.parse(lastUpdateStr);
    if (now.difference(lastUpdate).inHours < 12) {
      return;
    }
  }

  final sources = ['bcv', 'paralelo'];
  bool anyInserted = false;

  for (final source in sources) {
    try {
      final result = await RateProviderManager.instance.fetchRate(
        date: now,
        source: source,
      );

      if (result != null) {
        // Insert with source tag (new system)
        await ExchangeRateService.instance.insertOrUpdateExchangeRateWithSource(
          currencyCode: 'USD',
          date: now,
          rate: result.rate,
          source: source,
        );

        // For BCV, also insert without source for backwards compatibility
        // (existing display widgets use the source-less rate)
        if (source == 'bcv') {
          await ExchangeRateService.instance.insertOrUpdateExchangeRate(
            ExchangeRateInDB(
              id: generateUUID(),
              date: now,
              currencyCode: 'USD',
              exchangeRate: result.rate,
            ),
          );
        }

        debugPrint(
          'Currency rate auto-updated ($source): ${result.rate} '
          'via ${result.providerName}',
        );
        anyInserted = true;
      }
    } catch (e) {
      debugPrint('Error fetching $source rate: $e');
    }
  }

  // Also try the legacy DolarApi fetch for caching (used by other callers)
  try {
    await DolarApiService.instance.fetchAllRates();
  } catch (_) {}

  if (anyInserted) {
    await prefs.setString(
      'last_currency_auto_update_v3',
      now.toIso8601String(),
    );
  }
}
