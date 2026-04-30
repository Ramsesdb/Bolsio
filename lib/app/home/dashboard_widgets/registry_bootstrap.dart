import 'package:bolsio/app/home/dashboard_widgets/edit/exchange_rate_config_sheet.dart';
import 'package:bolsio/app/home/dashboard_widgets/edit/quick_use_config_sheet.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/account_carousel_widget.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/income_expense_period_widget.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/pending_imports_alert_widget.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/quick_use_widget.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/recent_transactions_widget.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/total_balance_summary_widget.dart';

/// Registers every dashboard widget spec into
/// [DashboardWidgetRegistry.instance].
///
/// Invoked once from `main.dart` BEFORE `runApp` so the dashboard renderer
/// always observes a fully populated registry on its first frame (see
/// `dashboard-widgets` § `DashboardWidgetRegistry` "MUST inicializarse
/// antes de runApp").
///
/// Cada wrapper expone su propia función `register{Type}Widget()` que
/// invocamos aquí en orden de aparición — el orden importa porque
/// [DashboardWidgetRegistry.all] preserva la inserción y de ahí se deriva
/// el catálogo del bottom sheet de "Agregar widget".
void registerDashboardWidgets() {
  registerTotalBalanceSummaryWidget();
  registerAccountCarouselWidget();
  registerIncomeExpensePeriodWidget();
  registerRecentTransactionsWidget();
  registerExchangeRateCardWidget();
  registerPendingImportsAlertWidget();
  registerQuickUseWidget();

  // Conecta el `configEditor` del spec `quickUse` al sheet concreto. La
  // indirección por callback global rompe el ciclo de imports
  // `widgets/quick_use_widget.dart` ↔ `edit/quick_use_config_sheet.dart`.
  quickUseConfigEditorBuilder = (context, descriptor) {
    return QuickUseConfigSheet(descriptor: descriptor);
  };

  // Conecta el `configEditor` del spec `exchangeRateCard` al sheet concreto.
  // Mismo patrón que `quickUse` — el builder global rompe el ciclo de imports
  // `widgets/exchange_rate_card_widget.dart` ↔
  // `edit/exchange_rate_config_sheet.dart`. Ver ADR-5 en
  // `openspec/changes/exchange-rate-widget-config/design.md`.
  exchangeRateConfigEditorBuilder = (context, descriptor) {
    return ExchangeRateConfigSheet(descriptor: descriptor);
  };
}
