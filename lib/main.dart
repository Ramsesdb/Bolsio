import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:monekin/app/auth/login_page.dart';
import 'package:monekin/app/auth/signup_page.dart';
import 'package:monekin/app/layout/page_switcher.dart';
import 'package:monekin/app/layout/widgets/app_navigation_sidebar.dart';
import 'package:monekin/app/layout/window_bar.dart';
import 'package:monekin/app/onboarding/intro.page.dart';
import 'package:monekin/core/database/services/app-data/app_data_service.dart';
import 'package:monekin/core/database/services/user-setting/private_mode_service.dart';
import 'package:monekin/core/database/services/user-setting/user_setting_service.dart';
import 'package:monekin/core/database/services/user-setting/utils/get_theme_from_string.dart';
import 'package:monekin/core/presentation/helpers/global_snackbar.dart';
import 'package:monekin/core/presentation/theme.dart';
import 'package:monekin/core/routes/handle_will_pop_scope.dart';
import 'package:monekin/core/routes/root_navigator_observer.dart';
import 'package:monekin/core/routes/route_utils.dart';
import 'package:monekin/core/services/firebase_sync_service.dart';
import 'package:monekin/core/utils/app_utils.dart';
import 'package:monekin/core/utils/keyboard_intents.dart';
import 'package:monekin/core/utils/logger.dart';
import 'package:monekin/core/utils/scroll_behavior_override.dart';
import 'package:monekin/core/utils/unique_app_widgets_keys.dart';
import 'package:monekin/i18n/generated/translations.g.dart';
import 'package:monekin/core/services/dolar_api_service.dart';
import 'package:monekin/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:monekin/core/models/exchange-rate/exchange_rate.dart';
import 'package:monekin/core/utils/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monekin/core/database/app_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    await FirebaseSyncService.instance.initialize();
  } catch (e) {
    // Firebase init can fail on some devices - app should still work offline
    debugPrint('Firebase initialization failed: $e');
  }

  // --- Auto-update Currency Rate (Daily) ---
  try {
    await _checkAndAutoUpdateCurrencyRate();
  } catch (e) {
    debugPrint('Error auto-updating currency rate: $e');
  }
  // -----------------------------------------

  await UserSettingService.instance.initializeGlobalStateMap();
  await AppDataService.instance.initializeGlobalStateMap();

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
  void refreshAppState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // ignore: prefer_const_constructors
    return MonekinAppEntryPoint(key: const ValueKey('App Entry Point'));
  }
}

class MonekinAppEntryPoint extends StatelessWidget {
  const MonekinAppEntryPoint({super.key});

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
          title: 'Monekin',
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

// Handles onboarding and authentication!
class InitialPageRouteNavigator extends StatelessWidget {
  const InitialPageRouteNavigator({super.key, required this.introSeen});

  final bool introSeen;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        Logger.printDebug(
          'AUTH STATE: connectionState=${snapshot.connectionState}, '
          'hasData=${snapshot.hasData}, user=${snapshot.data?.email}',
        );

        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Not logged in -> show login page
        if (!snapshot.hasData || snapshot.data == null) {
          return Navigator(
            key: navigatorKey,
            onGenerateRoute: (settings) {
              if (settings.name == '/signup') {
                return RouteUtils.getPageRouteBuilder(const SignupPage());
              }
              return RouteUtils.getPageRouteBuilder(const LoginPage());
            },
          );
        }

        // Logged in -> Check whitelist before allowing access
        return FutureBuilder<bool>(
          future: FirebaseSyncService.instance.isUserWhitelisted(),
          builder: (context, whitelistSnapshot) {
            // Still checking whitelist
            if (whitelistSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Verificando permisos...'),
                    ],
                  ),
                ),
              );
            }

            // Not whitelisted -> Sign out and show error
            if (whitelistSnapshot.data != true) {
              // Sign out immediately
              WidgetsBinding.instance.addPostFrameCallback((_) {
                FirebaseSyncService.instance.signOut();
              });

              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.block, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Acceso Denegado',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tu correo (${snapshot.data?.email}) no está '
                          'autorizado para usar esta aplicación.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Contacta al administrador para solicitar acceso.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Whitelisted -> Sync data and show main app
            FirebaseSyncService.instance.pullAllData();

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
          },
        );
      },
    );
  }
}

/// Helper to auto-update currency rate once a day
Future<void> _checkAndAutoUpdateCurrencyRate() async {
  final prefs = await SharedPreferences.getInstance();
  final lastUpdateStr = prefs.getString('last_currency_auto_update_v2');
  final now = DateTime.now();

  // If updated less than 24h ago, skip
  if (lastUpdateStr != null) {
    final lastUpdate = DateTime.parse(lastUpdateStr);
    if (now.difference(lastUpdate).inHours < 24) {
      return;
    }
  }

  // Fetch rates
  final rates = await DolarApiService.instance.fetchAllRates();
  if (rates.isEmpty) return;

  final oficial = DolarApiService.instance.oficialRate;
  if (oficial == null) return;

  // Insert rate
  await ExchangeRateService.instance.insertOrUpdateExchangeRate(
    ExchangeRateInDB(
      id: generateUUID(),
      date: now,
      currencyCode: 'USD',
      exchangeRate: oficial.promedio,
    ),
  );

  // Save new timestamp
  await prefs.setString('last_currency_auto_update_v2', now.toIso8601String());
  debugPrint('Currency rate auto-updated to: ${oficial.promedio}');
}
