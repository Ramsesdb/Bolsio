import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallex/app/budgets/budgets_page.dart';
import 'package:wallex/app/currencies/currency_manager.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/settings/settings_page.dart';
import 'package:wallex/app/stats/stats_page.dart';
import 'package:wallex/app/transactions/form/transaction_form.page.dart';
import 'package:wallex/app/transactions/transactions.page.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/private_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/transaction/transaction_type.enum.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

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
  QuickActionId.goToSettings: QuickAction(
    icon: Icons.settings_outlined,
    label: (ctx) => Translations.of(ctx).home.quick_actions.go_to_settings,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      RouteUtils.pushRoute(const SettingsPage());
    },
  ),
  QuickActionId.goToBudgets: QuickAction(
    icon: Icons.savings_outlined,
    label: (ctx) => Translations.of(ctx).home.quick_actions.go_to_budgets,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      RouteUtils.pushRoute(const BudgetsPage());
    },
  ),
  QuickActionId.goToReports: QuickAction(
    icon: Icons.bar_chart_rounded,
    label: (ctx) => Translations.of(ctx).home.quick_actions.go_to_reports,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      RouteUtils.pushRoute(const StatsPage());
    },
  ),
  QuickActionId.openTransactions: QuickAction(
    icon: Icons.receipt_long_outlined,
    label: (ctx) => Translations.of(ctx).home.quick_actions.open_transactions,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      RouteUtils.pushRoute(const TransactionsPage());
    },
  ),
  QuickActionId.openExchangeRates: QuickAction(
    icon: Icons.currency_exchange_rounded,
    label: (ctx) =>
        Translations.of(ctx).home.quick_actions.open_exchange_rates,
    category: QuickActionCategory.navigation,
    action: (ctx) {
      // Wallex no expone una "ExchangeRatesPage" raíz: el flujo canónico es
      // entrar al gestor de monedas, donde el usuario ve las tasas y puede
      // tocar una para abrir su detalle. Es el equivalente más cercano a
      // "abrir tasas" que pide el spec sin obligar a elegir divisa primero.
      RouteUtils.pushRoute(const CurrencyManagerPage());
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
