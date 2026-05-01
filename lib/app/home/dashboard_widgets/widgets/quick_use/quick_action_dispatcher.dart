import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nitido/app/budgets/budgets_page.dart';
import 'package:nitido/app/calculator/calculator.page.dart';
import 'package:nitido/app/currencies/currency_manager.dart';
import 'package:nitido/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:nitido/app/settings/settings_page.dart';
import 'package:nitido/app/stats/stats_page.dart';
import 'package:nitido/app/transactions/form/transaction_form.page.dart';
import 'package:nitido/app/transactions/transactions.page.dart';
import 'package:nitido/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:nitido/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:nitido/core/database/services/user-setting/private_mode_service.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/models/transaction/transaction_type.enum.dart';
import 'package:nitido/core/presentation/responsive/breakpoints.dart';
import 'package:nitido/core/routes/destinations.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/core/utils/logger.dart';
import 'package:nitido/core/utils/unique_app_widgets_keys.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

/// Categorías visuales del catálogo de quick actions. Usadas por
/// [QuickUseConfigSheet] para agrupar los chips disponibles.
enum QuickActionCategory { toggle, navigation, quickTx }

/// Descriptor inmutable de una quick action: ícono + label i18n + callback.
///
/// Las acciones se registran en [kQuickActions] como un mapa estático
/// indexado por [QuickActionId]. El widget `quickUse` usa este mapa para
/// renderizar chips y, al pulsarlos, invoca [QuickAction.action].
@immutable
class QuickAction {
  const QuickAction({
    required this.icon,
    required this.label,
    required this.action,
    required this.category,
    this.recommendedForGoals = const <String>{},
  });

  /// Ícono mostrado en el chip.
  final IconData icon;

  /// Builder de label i18n. Recibe el `BuildContext` del widget para que las
  /// acciones reactivas (`togglePreferredCurrency`) puedan leer el valor
  /// actual de `appStateSettings` al construir el texto. Wave 4 sustituirá
  /// los string literales por claves slang.
  final String Function(BuildContext context) label;

  /// Callback ejecutado al hacer tap en el chip. MUST tolerar contextos sin
  /// `Navigator` raíz (ej. lockscreen) — los navegadores fallan
  /// silenciosamente vía `RouteUtils.pushRoute`.
  final void Function(BuildContext context) action;

  /// Categoría del catálogo. Usada por [QuickUseConfigSheet] para agrupar
  /// chips en la pestaña "Atajos".
  final QuickActionCategory category;

  /// Goals para los que esta acción es relevante. Usado por la UI del
  /// editor para destacar atajos recomendados (no implementado en MVP).
  final Set<String> recommendedForGoals;
}

/// Catálogo estático de quick actions disponibles. Está indexado por
/// [QuickActionId] — añadir una entrada nueva exige también extender el
/// enum en `widget_descriptor.dart`.
///
/// Convenciones:
///   - **Toggles**: alternan estado de un service singleton existente. NO
///     vuelven a implementar lógica.
///   - **Navegación**: usan `RouteUtils.pushRoute`.
///   - **Quick transactions**: empujan `TransactionFormPage` con `mode`
///     preseleccionado.
final Map<QuickActionId, QuickAction> kQuickActions = <QuickActionId, QuickAction>{
  // ─────────── Toggles ───────────
  QuickActionId.togglePrivateMode: QuickAction(
    icon: Icons.visibility_off_outlined,
    label: (ctx) =>
        Translations.of(ctx).home.quick_actions.toggle_private_mode,
    category: QuickActionCategory.toggle,
    action: (ctx) async {
      final current = appStateSettings[SettingKey.privateMode] == '1';
      await PrivateModeService.instance.setPrivateMode(!current);
      await HapticFeedback.lightImpact();
    },
  ),
  QuickActionId.toggleHiddenMode: QuickAction(
    icon: Icons.lock_outline,
    label: (ctx) =>
        Translations.of(ctx).home.quick_actions.toggle_hidden_mode,
    category: QuickActionCategory.toggle,
    action: (ctx) async {
      // Solo togglea cuando la feature está habilitada — si está
      // deshabilitada, lock() es no-op y el usuario tiene que ir a
      // Settings > Hidden Mode para activarla. Reflejamos eso con un
      // log de debug (la UI reactiva no ofrecerá el chip si es relevante).
      final enabled = await HiddenModeService.instance.isEnabled();
      if (!enabled) {
        Logger.printDebug(
          '[QuickAction.toggleHiddenMode] feature disabled, no-op.',
        );
        return;
      }
      if (HiddenModeService.instance.isLocked) {
        // Desbloquear requiere PIN — el flujo canónico vive en
        // `dashboard.page.dart::_handleSecretTap` (long-press en el avatar).
        // El chip aquí solo soporta lock(); el unlock manual mantiene el
        // contrato de seguridad sin acoplar el dispatcher al modal de PIN.
        Logger.printDebug(
          '[QuickAction.toggleHiddenMode] currently locked — use the avatar '
          'long-press to enter the PIN. Chip is a no-op while locked.',
        );
      } else {
        HiddenModeService.instance.lock();
      }
      await HapticFeedback.lightImpact();
    },
  ),
  QuickActionId.togglePreferredCurrency: QuickAction(
    icon: Icons.swap_horiz_rounded,
    // Dynamic label: shows the active currency code so the user sees the
    // chip's current value at a glance. The accessibility label routes
    // through slang via the spec's [DashboardWidgetSpec.displayName].
    label: (ctx) =>
        appStateSettings[SettingKey.preferredCurrency] ?? 'USD',
    category: QuickActionCategory.toggle,
    action: (ctx) async {
      final current =
          appStateSettings[SettingKey.preferredCurrency] ?? 'USD';
      // Cicla USD → VES → DUAL → USD. DUAL es el caso multi-currency en el
      // que se muestran ambos balances (consultado en `s02_currency` del
      // onboarding). El spec acepta el ciclo aunque solo enumere USD↔VES;
      // mantenemos los tres estados que la app realmente usa.
      final next = switch (current) {
        'USD' => 'VES',
        'VES' => 'DUAL',
        _ => 'USD',
      };
      await UserSettingService.instance.setItem(
        SettingKey.preferredCurrency,
        next,
        updateGlobalState: true,
      );
      // Limpiar caché de tasas para forzar refresh de la conversión.
      await ExchangeRateService.instance.deleteExchangeRates();
      await HapticFeedback.lightImpact();
    },
  ),

  // ─────────── Navegación ───────────
  //
  // Bug-fix: las chips que apuntan a un destino que YA es un tab del bottom
  // navigation deben cambiar el tab activo en lugar de hacer push de una
  // pantalla nueva sobre el shell. Hacer push remontaba la pantalla y causaba
  // un parpadeo del bottom nav durante la transición — además rompía el flow
  // de tabs (el usuario quedaba en una página apilada con un back-button en
  // vez de poder cambiar libremente con el bottom nav).
  //
  // Tabs móviles reales (mobile layout, ver `getDestinations` en
  // `core/routes/destinations.dart` con filtro `isMobileMode`):
  //   - dashboard      → Inicio
  //   - transactions   → Transacciones
  //   - stats          → Estadísticas
  //   - settings       → Más (MoreActionsPage)
  //
  // Reglas de mapping aplicadas abajo:
  //   - Hay tab directo  → `_NavigationStrategy.switchTab` (cambia el tab del
  //     shell con `tabsPageKey.currentState?.changePage(...)`).
  //   - No hay tab       → push tradicional (BudgetsPage, SettingsPage,
  //     CurrencyManagerPage, CalculatorPage).
  QuickActionId.goToSettings: QuickAction(
    icon: Icons.settings_outlined,
    label: (ctx) => Translations.of(ctx).home.quick_actions.go_to_settings,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      // No hay tab dedicado a "Settings" — el tab "Más" abre MoreActionsPage,
      // pantalla distinta de SettingsPage. Mantenemos push.
      _QuickNav.push(const SettingsPage());
    },
  ),
  QuickActionId.goToBudgets: QuickAction(
    icon: Icons.savings_outlined,
    label: (ctx) => Translations.of(ctx).home.quick_actions.go_to_budgets,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      // Budgets no está en el bottom nav móvil (solo en sidebar desktop).
      _QuickNav.push(const BudgetsPage());
    },
  ),
  QuickActionId.goToReports: QuickAction(
    icon: Icons.bar_chart_rounded,
    label: (ctx) => Translations.of(ctx).home.quick_actions.go_to_reports,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      // Estadísticas SÍ es un tab → cambiar tab activo.
      _QuickNav.switchTabOrPush(
        AppMenuDestinationsID.stats,
        const StatsPage(),
        ctx,
      );
    },
  ),
  QuickActionId.openTransactions: QuickAction(
    icon: Icons.receipt_long_outlined,
    label: (ctx) => Translations.of(ctx).home.quick_actions.open_transactions,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      // Transacciones SÍ es un tab → cambiar tab activo.
      _QuickNav.switchTabOrPush(
        AppMenuDestinationsID.transactions,
        const TransactionsPage(),
        ctx,
      );
    },
  ),
  QuickActionId.openExchangeRates: QuickAction(
    icon: Icons.currency_exchange_rounded,
    label: (ctx) =>
        Translations.of(ctx).home.quick_actions.open_exchange_rates,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      // Nitido no expone una "ExchangeRatesPage" raíz: el flujo canónico es
      // entrar al gestor de monedas, donde el usuario ve las tasas y puede
      // tocar una para abrir su detalle. Es el equivalente más cercano a
      // "abrir tasas" que pide el spec sin obligar a elegir divisa primero.
      _QuickNav.push(const CurrencyManagerPage());
    },
  ),
  QuickActionId.goToCalculator: QuickAction(
    icon: Icons.calculate_outlined,
    label: (ctx) =>
        Translations.of(ctx).home.quick_actions.go_to_calculator,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      // Calculadora FX standalone (calculadora-fx Tanda 1, task 1.5).
      // NOTA: este chip NO está en el default `quickUse` set — solo
      // aparece en `QuickUseConfigSheet` para opt-in (per spec
      // REQ-CALC-8 "Quick action wiring is opt-in").
      _QuickNav.push(const CalculatorPage());
    },
  ),

  // ─────────── Quick transactions ───────────
  QuickActionId.newExpenseTransaction: QuickAction(
    icon: Icons.remove_circle_outline,
    label: (ctx) =>
        Translations.of(ctx).home.quick_actions.new_expense_transaction,
    category: QuickActionCategory.quickTx,
    action: (ctx) {
      RouteUtils.pushRoute(
        const TransactionFormPage(mode: TransactionType.expense),
      );
    },
  ),
  QuickActionId.newIncomeTransaction: QuickAction(
    icon: Icons.add_circle_outline,
    label: (ctx) =>
        Translations.of(ctx).home.quick_actions.new_income_transaction,
    category: QuickActionCategory.quickTx,
    action: (ctx) {
      RouteUtils.pushRoute(
        const TransactionFormPage(mode: TransactionType.income),
      );
    },
  ),
  QuickActionId.newTransferTransaction: QuickAction(
    icon: Icons.swap_vert_rounded,
    label: (ctx) =>
        Translations.of(ctx).home.quick_actions.new_transfer_transaction,
    category: QuickActionCategory.quickTx,
    action: (ctx) {
      RouteUtils.pushRoute(
        const TransactionFormPage(mode: TransactionType.transfer),
      );
    },
  ),
};

/// Despachador centralizado: resuelve un id (string) a su [QuickAction] y
/// ejecuta el callback. Tolera ids desconocidos (loguea y no-op) — esto
/// soporta el escenario "QuickActionId huérfano" del spec
/// `dashboard-quick-use` § Mapping action→callback.
class QuickActionDispatcher {
  const QuickActionDispatcher._();

  /// Resuelve [rawId] (el `name` del enum) y ejecuta su callback. Loguea y
  /// no-op cuando [rawId] no está registrado.
  static void run(String rawId, BuildContext context) {
    final id = QuickActionId.tryParse(rawId);
    if (id == null) {
      Logger.printDebug(
        '[QuickActionDispatcher] Unknown action id: "$rawId". Ignoring.',
      );
      return;
    }
    final entry = kQuickActions[id];
    if (entry == null) {
      Logger.printDebug(
        '[QuickActionDispatcher] No callback registered for ${id.name}.',
      );
      return;
    }
    entry.action(context);
  }

  /// Lookup directo por enum. Devuelve `null` si la acción no está en el
  /// catálogo (no debería ocurrir — todas las entradas del enum tienen su
  /// `QuickAction`).
  static QuickAction? get(QuickActionId id) => kQuickActions[id];
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper interno de navegación.
//
// Encapsula la decisión "switch tab vs push" en un solo lugar y expone
// hooks `@visibleForTesting` para que los tests puedan capturar invocaciones
// sin montar el shell completo (PageSwitcher + Navigator raíz).
// ─────────────────────────────────────────────────────────────────────────────

/// Firma del switch-tab. Devuelve `true` si efectivamente cambió el tab,
/// `false` si no hay shell montado (ej. lockscreen, tests sin pump del shell).
typedef _TabSwitcher = bool Function(AppMenuDestinationsID id);

/// Firma del fallback de push. La implementación real delega en
/// [RouteUtils.pushRoute]; los tests inyectan un capturador.
typedef _Pusher = void Function(Widget page);

class _QuickNav {
  const _QuickNav._();

  /// Implementación por defecto: usa el `tabsPageKey` global del shell. Si
  /// el shell no está montado (ej. unit tests sin pump del PageSwitcher),
  /// retorna `false` para que el caller haga fallback a push.
  static bool _defaultSwitchTab(AppMenuDestinationsID id) {
    final state = tabsPageKey.currentState;
    if (state == null) return false;
    state.changePage(id);
    return true;
  }

  static void _defaultPush(Widget page) {
    RouteUtils.pushRoute(page);
  }

  /// Hook de tests: reemplazar para capturar el id del tab al que se
  /// intenta cambiar. NO usar en producción.
  @visibleForTesting
  static _TabSwitcher tabSwitcher = _defaultSwitchTab;

  /// Hook de tests: reemplazar para capturar la página que se empujaría.
  /// NO usar en producción.
  @visibleForTesting
  static _Pusher pusher = _defaultPush;

  /// Restaura los hooks a sus implementaciones reales. Llamar en
  /// `tearDown` de los tests.
  @visibleForTesting
  static void resetForTesting() {
    tabSwitcher = _defaultSwitchTab;
    pusher = _defaultPush;
  }

  /// Cambia el tab activo del bottom navigation cuando estamos en layout
  /// móvil y existe un tab para [id]; en cualquier otro caso (desktop, tab
  /// no presente, shell no montado) hace push de [fallbackPage].
  ///
  /// El [BuildContext] se usa solo para detectar el breakpoint — no se
  /// guarda referencia a él.
  static void switchTabOrPush(
    AppMenuDestinationsID id,
    Widget fallbackPage,
    BuildContext context,
  ) {
    if (_isTabAvailableForCurrentLayout(id, context)) {
      final switched = tabSwitcher(id);
      if (switched) return;
      // El shell no estaba montado por algún motivo — degradamos a push.
    }
    pusher(fallbackPage);
  }

  /// Push directo. Centralizado aquí para que los tests puedan observar
  /// las navegaciones que NO mapean a tab (Settings, Budgets, ExchangeRates,
  /// Calculator) con el mismo seam.
  static void push(Widget page) {
    pusher(page);
  }

  /// Devuelve `true` si [id] es uno de los tabs visibles en el layout
  /// actual. En desktop el bottom nav no se muestra (ver `PageSwitcher`),
  /// así que preferimos push para mantener el comportamiento existente.
  static bool _isTabAvailableForCurrentLayout(
    AppMenuDestinationsID id,
    BuildContext context,
  ) {
    final isMobile = BreakPoint.of(context).isSmallerThan(BreakpointID.md);
    if (!isMobile) return false;
    // Tabs reales del bottom nav en mobile (ver `getDestinations` con
    // filtro `isMobileMode` en `core/routes/destinations.dart`).
    const mobileTabs = <AppMenuDestinationsID>{
      AppMenuDestinationsID.dashboard,
      AppMenuDestinationsID.transactions,
      AppMenuDestinationsID.stats,
      AppMenuDestinationsID.settings,
    };
    return mobileTabs.contains(id);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test hooks públicos.
//
// `_QuickNav` es privada al archivo (lleva guion bajo). Los tests viven en
// otra librería — no pueden acceder a símbolos privados —, así que exponemos
// los hooks vía esta fachada `@visibleForTesting`. El analyzer marcará una
// advertencia si se invoca desde código de producción.
// ─────────────────────────────────────────────────────────────────────────────
@visibleForTesting
class QuickActionDispatcherTestHooks {
  const QuickActionDispatcherTestHooks._();

  static void installTabSwitcher(bool Function(AppMenuDestinationsID) fn) {
    _QuickNav.tabSwitcher = fn;
  }

  static void installPusher(void Function(Widget) fn) {
    _QuickNav.pusher = fn;
  }

  static void resetHooks() {
    _QuickNav.resetForTesting();
  }
}
