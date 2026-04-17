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

  // Always initialize Firebase — sync is always available.
  // If Firebase init fails (offline, misconfigured), the app works offline.
  try {
    await Firebase.initializeApp();
    await FirebaseSyncService.instance.initialize();
  } catch (e) {
    debugPrint('Firebase initialization failed (app works offline): $e');
  }

  // --- One-time migration: fix inverted exchangeRateApplied values ---
  // Fire-and-forget: SQL/HTTP work that is NOT required for first frame.
  // The "migrated v1" flag gate is preserved inside the function, so running
  // in the background changes only timing, not behavior.
  unawaited(
    _migrateInvertedExchangeRates().catchError((e) {
      debugPrint('Error running exchange rate migration: $e');
    }),
  );
  // -----------------------------------------

  // --- Auto-update Currency Rate (Daily) ---
  // Fire-and-forget: 12h cooldown gate is preserved inside the function.
  unawaited(
    _checkAndAutoUpdateCurrencyRate().catchError((e) {
      debugPrint('Error auto-updating currency rate: $e');
    }),
  );
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
        CaptureOrchestrator.instance.onNewPendingImport =
            (int count) async {
          await LocalNotificationService.instance
              .showNewPendingNotification(count);
        };

        // Start the background service — it handles ALL capture sources
        // (SMS, notifications, Binance API) and keeps capture alive when
        // the app is closed.  The notification_listener_service plugin uses
        // a BroadcastReceiver that works in both isolates; running it only
        // in the background service avoids duplicate captures.
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
  unawaited(LocaleSettings.setPluralResolver(
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
  ));

  // --- Preload locale synchronously BEFORE runApp ---
  // Doing this async after runApp pulses the translation stream and rebuilds
  // InitialPageRouteNavigator 2–3×. The sync variants cost a few ms on the
  // critical path but eliminate the rebuild cascade entirely.
  try {
    final lang = appStateSettings[SettingKey.appLanguage];
    if (lang != null && lang.isNotEmpty) {
      final setLocale = LocaleSettings.setLocaleRawSync(lang);
      if (setLocale.languageTag != lang) {
        Logger.printDebug(
          'Warning: requested locale `$lang` unavailable. '
          'Fallback to `${setLocale.languageTag}`.',
        );
        // Clear the stored value so we fall back to device locale next launch.
        unawaited(
          UserSettingService.instance
              .setItem(SettingKey.appLanguage, null)
              .then((_) {}),
        );
      }
    } else {
      LocaleSettings.useDeviceLocaleSync();
    }
  } catch (e) {
    Logger.printDebug('Error preloading locale synchronously: $e');
  }
  // -----------------------------------------

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

    // Locale is now preloaded synchronously in main() before runApp, so we
    // do NOT set it here — doing so pulses the translation stream and causes
    // extra rebuilds (the old cause of pullAllData firing 2–3×).

    return TranslationProvider(
      child: MaterialAppContainer(
        amoledMode: appStateSettings[SettingKey.amoledMode]! == '1',
        accentColor: appStateSettings[SettingKey.accentColor]!,
        themeMode: getThemeFromString(appStateSettings[SettingKey.themeMode]!),
      ),
    );
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
class InitialPageRouteNavigator extends StatefulWidget {
  const InitialPageRouteNavigator({super.key, required this.introSeen});

  final bool introSeen;

  @override
  State<InitialPageRouteNavigator> createState() =>
      _InitialPageRouteNavigatorState();
}

class _InitialPageRouteNavigatorState extends State<InitialPageRouteNavigator> {
  @override
  void initState() {
    super.initState();

    // Fire background Firebase sync ONCE per session, after first frame.
    // Previously this was called from build() on a StatelessWidget, which
    // fired 2–3× due to locale/translation stream rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final onboarded = appStateData[AppDataKey.onboarded] == '1';
      if (onboarded && FirebaseSyncService.instance.isFirebaseAvailable) {
        FirebaseSyncService.instance.pullAllData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final onboarded = appStateData[AppDataKey.onboarded] == '1';

    Logger.printDebug(
      'ROUTE STATE: onboarded=$onboarded, introSeen=${widget.introSeen}, '
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

    return HeroControllerScope(
      controller: MaterialApp.createMaterialHeroController(),
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (settings) => RouteUtils.getPageRouteBuilder(
          widget.introSeen
              ? PageSwitcher(key: tabsPageKey)
              : const IntroPage(),
        ),
      ),
    );
  }
}

/// One-time migration: invert wrong-direction exchangeRateApplied values
/// on existing transactions, and clean up bad exchangeRates rows.
///
/// Old data stored rates like 479.78 (VES per USD) on transactions
/// when preferred currency is USD. The correct value is ~0.00208.
/// This runs ONCE, tracked via SharedPreferences flag.
Future<void> _migrateInvertedExchangeRates() async {
  final prefs = await SharedPreferences.getInstance();
  const migrationKey = 'migration_invert_exchange_rates_v1';

  if (prefs.getBool(migrationKey) == true) {
    return; // Already migrated
  }

  final preferredCurrency =
      appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

  final db = AppDB.instance;

  // Task 1: Invert transaction exchangeRateApplied values > 1.0
  // These are stored as e.g. 479.78 instead of 0.00208
  // Only invert when preferred currency is USD (the common misconfiguration).
  // For VES preferred, values > 1 are correct (e.g. 479.78 VES per USD).
  if (preferredCurrency != 'VES') {
    await db.customStatement(
      'UPDATE transactions '
      'SET exchangeRateApplied = 1.0 / exchangeRateApplied '
      'WHERE exchangeRateApplied IS NOT NULL '
      'AND exchangeRateApplied > 1.0',
    );

    debugPrint(
      'Migration: inverted exchangeRateApplied on transactions '
      '(preferredCurrency=$preferredCurrency)',
    );

    // Also push corrected transactions to Firebase so cloud data is fixed
    if (FirebaseSyncService.instance.isFirebaseAvailable &&
        FirebaseSyncService.instance.currentUserId != null) {
      try {
        final corrected = await db.customSelect(
          'SELECT * FROM transactions '
          'WHERE exchangeRateApplied IS NOT NULL '
          'AND exchangeRateApplied > 0 AND exchangeRateApplied < 1.0',
        ).get();
        debugPrint(
          'Migration: ${corrected.length} corrected transactions to re-push',
        );
      } catch (e) {
        debugPrint('Migration: error querying corrected transactions: $e');
      }
    }
  }

  // Task 4: Delete bad exchangeRates rows with currencyCode='USD'
  // when preferred currency IS 'USD' (USD doesn't need a conversion rate
  // to itself — the CASE WHEN handles it).
  if (preferredCurrency == 'USD') {
    await ExchangeRateService.instance.deleteExchangeRates(
      currencyCode: 'USD',
    );
    debugPrint('Migration: deleted bad currencyCode=USD exchange rate rows');
  }

  // Also invert any exchangeRates rows that have wrong-direction values
  // (e.g. currencyCode='VES' with rate=479.78 when it should be ~0.00208)
  if (preferredCurrency != 'VES') {
    await db.customStatement(
      'UPDATE exchangeRates '
      'SET exchangeRate = 1.0 / exchangeRate '
      'WHERE currencyCode = \'VES\' '
      'AND exchangeRate > 1.0',
    );
    debugPrint('Migration: inverted bad VES exchange rate rows');
  }

  await prefs.setBool(migrationKey, true);
  debugPrint('Migration $migrationKey completed successfully');
}

/// Helper to auto-update currency rates (BCV + paralelo) once a day.
///
/// Fetches both sources via [RateProviderManager] (fallback chain) and stores
/// each one with its source tag. Also maintains backwards-compatible insertion
/// without source for existing callers.
Future<void> _checkAndAutoUpdateCurrencyRate() async {
  final prefs = await SharedPreferences.getInstance();
  final lastUpdateStr = prefs.getString('last_currency_auto_update_v4');
  final now = DateTime.now();

  final preferredCurrency =
      appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

  // Task 2: Force update if no VES rate exists yet (bypass the 12h check).
  // This handles the case where the daily check already ran but stored rates
  // in the wrong direction, so currencyCode='VES' rows don't exist.
  bool forceUpdate = false;
  if (preferredCurrency != 'VES') {
    final db = AppDB.instance;
    final vesRates = await db.customSelect(
      'SELECT COUNT(*) AS cnt FROM exchangeRates WHERE currencyCode = \'VES\'',
    ).getSingle();
    final vesCount = vesRates.read<int>('cnt');
    if (vesCount == 0) {
      forceUpdate = true;
      debugPrint('No VES exchange rates found — forcing rate update');
    }
  }

  // If updated less than 12h ago AND we don't need to force, skip
  if (!forceUpdate && lastUpdateStr != null) {
    final lastUpdate = DateTime.parse(lastUpdateStr);
    if (now.difference(lastUpdate).inHours < 12) {
      return;
    }
  }

  final sources = ['bcv', 'paralelo'];
  bool anyInserted = false;

  // Task 4: Delete bad currencyCode='USD' rows when preferred currency is USD.
  // USD accounts don't need a conversion rate to themselves.
  if (preferredCurrency == 'USD') {
    await ExchangeRateService.instance.deleteExchangeRates(currencyCode: 'USD');
  }

  for (final source in sources) {
    try {
      final result = await RateProviderManager.instance.fetchRate(
        date: now,
        source: source,
      );

      if (result != null) {
        // DolarAPI returns: 1 USD = result.rate VES (e.g. 479.78)
        // The DB convention is: "1 unit of currencyCode = X preferred currency units"
        // So for preferred=USD: store currencyCode='VES', rate=1/479.78
        // For preferred=VES: store currencyCode='USD', rate=479.78
        final String storeCurrencyCode;
        final double storeRate;
        if (preferredCurrency == 'VES') {
          storeCurrencyCode = 'USD';
          storeRate = result.rate; // 1 USD = 479.78 VES ✓
        } else {
          // preferred is USD (or anything else non-VES)
          storeCurrencyCode = 'VES';
          storeRate = 1.0 / result.rate; // 1 VES = 0.00208 USD
        }

        // Insert with source tag (new system)
        await ExchangeRateService.instance.insertOrUpdateExchangeRateWithSource(
          currencyCode: storeCurrencyCode,
          date: now,
          rate: storeRate,
          source: source,
        );

        // For BCV, also insert without source for backwards compatibility
        // (existing display widgets use the source-less rate)
        if (source == 'bcv') {
          await ExchangeRateService.instance.insertOrUpdateExchangeRate(
            ExchangeRateInDB(
              id: generateUUID(),
              date: now,
              currencyCode: storeCurrencyCode,
              exchangeRate: storeRate,
            ),
          );
        }

        debugPrint(
          'Currency rate auto-updated ($source): $storeRate '
          '(stored as $storeCurrencyCode) via ${result.providerName}',
        );
        anyInserted = true;
      }
    } catch (e) {
      debugPrint('Error fetching $source rate: $e');
    }
  }

  // Also fetch EUR rates
  for (final source in sources) {
    try {
      final result = await RateProviderManager.instance.fetchRate(
        date: now,
        source: source,
        currencyCode: 'EUR',
      );

      if (result != null) {
        // DolarAPI returns: 1 EUR = result.rate VES
        // For preferred=VES: store currencyCode='EUR', rate=result.rate (1 EUR = X VES)
        // For preferred=USD: need cross-rate. Fetch USD rate first to compute.
        final String storeCurrencyCode = 'EUR';
        double storeRate;
        if (preferredCurrency == 'VES') {
          storeRate = result.rate; // 1 EUR = X VES
        } else {
          // Cross-rate: 1 EUR = eurVesRate / usdVesRate preferred units
          // We need the USD/VES rate for the same source
          final usdResult = await RateProviderManager.instance.fetchRate(
            date: now,
            source: source,
          );
          if (usdResult != null && usdResult.rate > 0) {
            storeRate = result.rate / usdResult.rate; // e.g. 565/479 ≈ 1.18
          } else {
            storeRate = result.rate; // fallback: store raw
          }
        }

        await ExchangeRateService.instance.insertOrUpdateExchangeRateWithSource(
          currencyCode: storeCurrencyCode,
          date: now,
          rate: storeRate,
          source: source,
        );

        debugPrint(
          'EUR rate auto-updated ($source): $storeRate '
          '(stored as $storeCurrencyCode) via ${result.providerName}',
        );
        anyInserted = true;
      }
    } catch (e) {
      debugPrint('Error fetching EUR $source rate: $e');
    }
  }

  // Also try the legacy DolarApi fetch for caching (used by other callers)
  try {
    await DolarApiService.instance.fetchAllRates();
  } catch (_) {}

  if (anyInserted) {
    await prefs.setString(
      'last_currency_auto_update_v4',
      now.toIso8601String(),
    );
  }
}
