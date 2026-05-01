import 'dart:async' show unawaited;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:nitido/app/auth/biometric_lock_screen.dart';
import 'package:nitido/app/auth/welcome_screen.dart';
import 'package:nitido/app/home/dashboard_widgets/registry_bootstrap.dart';
import 'package:nitido/app/layout/page_switcher.dart';
import 'package:nitido/app/layout/widgets/app_navigation_sidebar.dart';
import 'package:nitido/app/layout/window_bar.dart';
import 'package:nitido/app/onboarding/onboarding.dart';
import 'package:nitido/core/database/services/app-data/app_data_service.dart';
import 'package:nitido/core/database/services/shared/key_value_service.dart';
import 'package:nitido/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:nitido/core/database/services/user-setting/private_mode_service.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/database/services/user-setting/utils/get_theme_from_string.dart';
import 'package:nitido/core/presentation/helpers/global_snackbar.dart';
import 'package:nitido/core/presentation/theme.dart';
import 'package:nitido/core/routes/handle_will_pop_scope.dart';
import 'package:nitido/core/routes/root_navigator_observer.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/core/services/firebase_sync_service.dart';
import 'package:nitido/core/services/ai/ai_credentials_store.dart';
import 'package:nitido/core/services/attachments/attachments_service.dart';
import 'package:nitido/core/utils/app_utils.dart';
import 'package:nitido/core/utils/keyboard_intents.dart';
import 'package:nitido/core/utils/logger.dart';
import 'package:nitido/core/utils/scroll_behavior_override.dart';
import 'package:nitido/core/utils/unique_app_widgets_keys.dart';
import 'package:nitido/i18n/generated/translations.g.dart';
import 'package:nitido/core/services/auto_import/background/local_notification_service.dart';
import 'package:nitido/core/services/auto_import/background/nitido_background_service.dart';
import 'package:nitido/core/services/auto_import/capture/capture_health_monitor.dart';
import 'package:nitido/core/models/auto_import/capture_channel.dart';
import 'package:nitido/core/services/auto_import/orchestrator/capture_orchestrator.dart';
import 'package:nitido/app/transactions/auto_import/pending_imports.page.dart';
import 'package:nitido/core/services/rate_providers/rate_refresh_service.dart';
import 'package:nitido/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:nitido/core/services/statement_import/statement_batches_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nitido/core/database/app_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hold the native splash screen while Vulkan shader pipelines compile.
  // The first 3 frames take ~85 ms each on cold start; deferring the first
  // frame keeps the OS splash visible until we explicitly call allowFirstFrame,
  // so the user never sees the shader-compilation jank.
  // This only runs on cold start — warm/hot restarts do not re-enter main().
  WidgetsBinding.instance.deferFirstFrame();

  // Wire the KeyValueService refresh hook to the live root state. The base
  // service avoids importing main.dart (so unit tests for any subclass can
  // run without pulling the full app graph); we install the callback here
  // before the first setItem can fire from app startup code.
  onGlobalAppStateRefresh = () {
    appStateKey.currentState?.refreshAppState();
  };

  // Initialize settings first so we can check the sync flag
  await UserSettingService.instance.initializeGlobalStateMap();
  await AppDataService.instance.initializeGlobalStateMap();

  // One-time migration: move pre-BYOK Nexus credentials into the new
  // per-provider store. Idempotent — subsequent runs no-op.
  unawaited(
    AiCredentialsStore.instance.migrateFromLegacyStore().catchError((e) {
      debugPrint('AiCredentialsStore.migrateFromLegacyStore error: $e');
      return false;
    }),
  );

  // Must complete BEFORE runApp: visibleAccountIdsStream seeds from the
  // locked state, and a late init lets the dashboard render with
  // `visibleIds == null` for the first frame — leaking saving accounts.
  await HiddenModeService.instance.init();

  // Populate the dashboard widget registry BEFORE runApp so the dashboard
  // renderer always observes a fully populated registry on its first frame
  // (see dashboard-widgets spec § DashboardWidgetRegistry).
  registerDashboardWidgets();

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

  // --- One-time migration: purge legacy color/type fields on Firestore
  // subcategory docs (see cleanupLegacySubcategoryFields for context).
  // Fire-and-forget: gated internally by a SharedPreferences flag, no-ops
  // when Firebase sync is not initialized or the user is signed out.
  unawaited(
    FirebaseSyncService.instance.cleanupLegacySubcategoryFields().catchError((
      e,
    ) {
      debugPrint('Error running Firebase subcategory cleanup: $e');
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

  if (kDebugMode) {
    // Debug-only housekeeping to keep attachment storage clean while iterating.
    unawaited(
      AttachmentsService.instance
          .purgeOrphans()
          .then((removed) {
            debugPrint('purgeOrphans removed $removed items');
          })
          .catchError((e) {
            debugPrint('purgeOrphans error: $e');
          }),
    );
  }

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

  // --- Background service + Auto-import bootstrap (DEFERRED) ---
  // The background service spins up a second Flutter engine (second
  // libflutter.so load) which visibly delays the cold-start frame on MIUI /
  // HyperOS. We configure + start the service 3s AFTER the first frame so the
  // main UI renders immediately; the service is not needed to paint the UI.
  final autoImportEnabled =
      appStateSettings[SettingKey.autoImportEnabled] == '1';

  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(seconds: 8), () {
      unawaited(
        NitidoBackgroundService.instance
            .initialize()
            .then((_) async {
              if (autoImportEnabled) {
                // Wire the orchestrator's callback so the main isolate can show
                // local notifications when a new pending import arrives.
                CaptureOrchestrator.instance.onNewPendingImport =
                    (int count) async {
                      await LocalNotificationService.instance
                          .showNewPendingNotification(count);
                    };

                // The notification EventChannel is bound to the main FlutterEngine,
                // so the background isolate excludes it — the main isolate must
                // own the notification capture source and its health monitor.
                unawaited(
                  CaptureOrchestrator.instance
                      .applySettings(channels: {CaptureChannel.notification})
                      .catchError((e) {
                        debugPrint(
                          'CaptureOrchestrator.applySettings (main isolate) error: $e',
                        );
                      }),
                );

                // Start the background service — it handles ALL capture sources
                // (SMS, notifications, Binance API) and keeps capture alive when
                // the app is closed.  The notification_listener_service plugin uses
                // a BroadcastReceiver that works in both isolates; running it only
                // in the background service avoids duplicate captures.
                await NitidoBackgroundService.instance.startService();
              }
            })
            .catchError((e) {
              debugPrint('Auto-import bootstrap error: $e');
            })
            .whenComplete(() {
              // Mark startup window as closed so the lifecycle watchdog
              // is now allowed to trigger background service restarts.
              appStateKey.currentState?._startupComplete = true;
            }),
      );
    });
  });
  // ---------------------------------------------------

  // Initial state: ON if the user asked us to start locked, OR if the user
  // left the runtime toggle ON in the previous session. This keeps the
  // toggle sticky across restarts (FIX: was only reading privateModeAtLaunch).
  unawaited(
    PrivateModeService.instance.setPrivateMode(
      appStateSettings[SettingKey.privateModeAtLaunch] == '1' ||
          appStateSettings[SettingKey.privateMode] == '1',
    ),
  );

  // Set plural resolver for Turkish
  unawaited(
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
    ),
  );

  // --- Preload locale asynchronously BEFORE runApp ---
  // slang uses deferred imports for locale libs, so the *Sync variants fail
  // at runtime with "Deferred library l_xx was not loaded". Awaiting the
  // async version here still guarantees the locale is ready before the first
  // frame, avoiding the translation-stream pulse that caused extra rebuilds.
  try {
    final lang = appStateSettings[SettingKey.appLanguage];
    if (lang != null && lang.isNotEmpty) {
      final setLocale = await LocaleSettings.setLocaleRaw(lang);
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
      await LocaleSettings.useDeviceLocale();
    }
  } catch (e) {
    debugPrint('Error preloading locale: $e');
  }
  // -----------------------------------------

  debugPaintSizeEnabled = false;
  runApp(InitializeApp(key: appStateKey));

  // Release the native splash after 1.5 s to let Vulkan shader pipelines
  // finish compiling in the background before the user sees interactive UI.
  await Future.delayed(const Duration(milliseconds: 1500));
  WidgetsBinding.instance.allowFirstFrame();
}

// ignore: library_private_types_in_public_api
GlobalKey<_InitializeAppState> appStateKey = GlobalKey();

class InitializeApp extends StatefulWidget {
  const InitializeApp({super.key});

  @override
  State<InitializeApp> createState() => _InitializeAppState();
}

class _InitializeAppState extends State<InitializeApp>
    with WidgetsBindingObserver {
  bool _biometricPassed = false;

  /// Guard for the lifecycle watchdog: true once the post-frame background
  /// service startup path has fired. Prevents the watchdog from doubling up
  /// with the deferred post-frame startup during the first few seconds of
  /// a cold start.
  bool _startupComplete = false;

  @override
  void initState() {
    super.initState();
    // HiddenModeService.init() is awaited in main() before runApp so the
    // lock state is authoritative by the first frame. Here we only hook the
    // lifecycle observer so the app re-locks when it goes to background.
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addObserver(HiddenModeService.instance);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeObserver(HiddenModeService.instance);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only run the watchdog after the post-frame startup path has completed.
      // During the first few seconds of a cold start the deferred
      // addPostFrameCallback path is already scheduling the service; firing
      // again here would cause a double-start race.
      if (!_startupComplete) return;
      unawaited(_ensureAutoImportServiceHealthy());
    }
  }

  Future<void> _ensureAutoImportServiceHealthy() async {
    final autoImportEnabled =
        appStateSettings[SettingKey.autoImportEnabled] == '1';
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (!autoImportEnabled || !isAndroid) return;

    try {
      await NitidoBackgroundService.instance.initialize();
      final isRunning = await NitidoBackgroundService.instance.isRunning();

      if (!isRunning) {
        await NitidoBackgroundService.instance.startService();
        debugPrint(
          'AutoImport watchdog: background service was down on resume and was restarted',
        );
      } else {
        // Cheap liveness poke: triggers an immediate health tick + optional
        // re-subscribe if the listener drifted into stale/zombie state.
        await CaptureHealthMonitor.instance.forceCheck();
      }
    } catch (e) {
      debugPrint('AutoImport watchdog: resume health check failed: $e');
    }
  }

  void refreshAppState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Skip the lock entirely when there is no user session yet (pre-onboarding
    // installs). Locking the WelcomeScreen has no protective value and breaks
    // first-impression UX. `appStateData` is hydrated synchronously in main()
    // before runApp(), so no flicker.
    final hasSession = appStateData[AppDataKey.onboarded] == '1';
    final biometricEnabled =
        appStateSettings[SettingKey.biometricEnabled] == '1';
    if (hasSession && biometricEnabled && !_biometricPassed) {
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
    return NitidoAppEntryPoint(key: const ValueKey('App Entry Point'));
  }
}

class NitidoAppEntryPoint extends StatelessWidget {
  const NitidoAppEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    Logger.printDebug('------------------ APP ENTRY POINT ------------------');

    // Locale is preloaded asynchronously in main() before runApp, so we do
    // NOT set it here — doing so pulses the translation stream and causes
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
          title: 'Nitido',
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
          // Instant theme swap (no cross-fade) — avoids thrashing animated
          // children (e.g. ExpandableFab) during the transition, which was
          // stalling the FAB fan after an accent color change.
          themeAnimationDuration: Duration.zero,
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
/// 2. If onboarded but introSeen is false → OnboardingPage (currency/category setup)
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
    //
    // Pull guard (Fix 2 Opción A): if WelcomeScreen already issued a pull
    // within the last 60s (it stamps `AppDataKey.lastPullAt` before its
    // own pullAllData), skip this one. Cold-start with an existing session
    // does NOT pass through WelcomeScreen, so `lastPullAt` is either absent
    // or stale and this branch still runs as before.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final onboarded = appStateData[AppDataKey.onboarded] == '1';
      if (!onboarded || !FirebaseSyncService.instance.isFirebaseAvailable) {
        return;
      }

      final lastPullAtRaw = appStateData[AppDataKey.lastPullAt];
      final lastPullAt = int.tryParse(lastPullAtRaw ?? '');
      if (lastPullAt != null) {
        final ageMs = DateTime.now().millisecondsSinceEpoch - lastPullAt;
        if (ageMs < 60 * 1000) {
          Logger.printDebug(
            'InitialPageRouteNavigator: skipping pullAllData '
            '(last pull ${ageMs}ms ago, < 60s window)',
          );
          return;
        }
      }

      FirebaseSyncService.instance.pullAllData();
      // Stamp so subsequent rebuilds within this session also short-circuit.
      AppDataService.instance.setItem(
        AppDataKey.lastPullAt,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
    });

    // Purge statement import batches older than 7 days on each session start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StatementBatchesService.instance.purge().catchError((e) {
        debugPrint('StatementBatchesService.purge error: $e');
      });
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
          widget.introSeen ? PageSwitcher(key: tabsPageKey) : const OnboardingPage(),
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
        final corrected = await db
            .customSelect(
              'SELECT * FROM transactions '
              'WHERE exchangeRateApplied IS NOT NULL '
              'AND exchangeRateApplied > 0 AND exchangeRateApplied < 1.0',
            )
            .get();
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
    await ExchangeRateService.instance.deleteExchangeRates(currencyCode: 'USD');
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
/// Thin wrapper that delegates to [RateRefreshService.runWithGate], which
/// honors the 12h cooldown gate and emits diagnostic log lines for both the
/// current cooldown timestamp and the skip/run decision.
Future<void> _checkAndAutoUpdateCurrencyRate() async {
  await RateRefreshService.instance.runWithGate();
}
