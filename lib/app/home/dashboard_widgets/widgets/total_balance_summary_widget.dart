import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:wallex/app/home/dashboard_widgets/dashboard_scope.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';
import 'package:wallex/app/home/widgets/balance_delta_pill.dart';
import 'package:wallex/app/home/widgets/click_tracker.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/private_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/presentation/responsive/breakpoints.dart';
import 'package:wallex/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:wallex/core/presentation/widgets/tappable.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Widget público que muestra el balance total convertido a la moneda
/// preferida (con su equivalente en VES) y permite alternar la fuente de
/// tasas (BCV / Paralelo).
///
/// Es el extracto público de `dashboard.page.dart::totalBalanceIndicator`
/// — la lógica y la UI permanecen idénticas. Wave 2 reemplazará la llamada
/// inline del dashboard por una entrada de layout dinámico que delega aquí.
///
/// El widget gestiona internamente las suscripciones a [HiddenModeService]
/// (vía `visibleAccountIdsStream` que ya hace `shareValue`), [AccountService]
/// y [ExchangeRateService]. La fuente de tasas se controla desde fuera para
/// que `IncomeOrExpenseCard` y este widget compartan el mismo valor: el
/// dashboard mantiene `_rateSource` en su `State` y propaga el cambio a
/// ambos hijos.
class TotalBalanceSummaryWidget extends StatefulWidget {
  const TotalBalanceSummaryWidget({
    super.key,
    required this.dateRangeService,
    required this.rateSource,
    required this.onRateSourceChanged,
    this.displayCurrency,
    this.showDeltaPill = true,
    this.alignStart = true,
    this.refreshTick = 0,
  });

  /// Periodo activo del dashboard. Se usa para el cálculo de la variación
  /// de balance (delta pill).
  final DatePeriodState dateRangeService;

  /// Fuente de tasas activa (`'bcv'` o `'paralelo'`). El widget no la
  /// persiste por sí mismo — el padre la mantiene en su `State` y la
  /// reescribe en `SettingKey.preferredRateSource` al cambiarla.
  final String rateSource;

  /// Callback invocado cuando el usuario cambia la fuente de tasas vía los
  /// chips internos. El padre debe persistir y propagar el nuevo valor a
  /// otros widgets dependientes (cards de Gasto/Ingreso).
  final ValueChanged<String> onRateSourceChanged;

  /// Moneda preferida para el total. Cuando es `null` se resuelve desde
  /// `appStateSettings[SettingKey.preferredCurrency]` (default `'USD'`).
  final String? displayCurrency;

  /// Cuando es `true` se muestra la delta pill al final si el periodo tiene
  /// rango definido. `false` la oculta (caso futuros widgets compactos).
  final bool showDeltaPill;

  /// `true` alinea los textos al inicio (caso layout horizontal cuando
  /// gasto/ingreso van al lado). `false` los centra (caso vertical / móvil
  /// estrecho).
  final bool alignStart;

  /// Contador externo para forzar la regeneración de streams (pull-to-refresh).
  /// Incrementar este valor en el padre dispara `didUpdateWidget` y reasigna
  /// las suscripciones — equivalente al `setState` que hacía
  /// `_DashboardPageState._refreshData`.
  final int refreshTick;

  @override
  State<TotalBalanceSummaryWidget> createState() =>
      _TotalBalanceSummaryWidgetState();
}

class _TotalBalanceSummaryWidgetState extends State<TotalBalanceSummaryWidget> {
  late Stream<double> _totalBalanceStream;
  late Stream<double> _totalBalanceInVesStream;
  late Stream<double> _balanceVariationStream;

  @override
  void initState() {
    super.initState();
    _rebuildStreams();
  }

  @override
  void didUpdateWidget(covariant TotalBalanceSummaryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-genera los streams cuando cambia la fuente de tasas, el periodo o
    // la moneda preferida — comportamiento idéntico a `_refreshData` y al
    // `setState` del chip selector en `dashboard.page.dart`.
    if (oldWidget.rateSource != widget.rateSource ||
        oldWidget.dateRangeService.startDate !=
            widget.dateRangeService.startDate ||
        oldWidget.dateRangeService.endDate !=
            widget.dateRangeService.endDate ||
        oldWidget.displayCurrency != widget.displayCurrency ||
        oldWidget.refreshTick != widget.refreshTick) {
      _rebuildStreams();
    }
  }

  void _rebuildStreams() {
    _balanceVariationStream = _getBalanceVariationStream();
    _totalBalanceStream = _getTotalBalanceStream();
    _totalBalanceInVesStream = _getTotalBalanceInVesStream();
  }

  /// Combina cuentas + visibilidad — espejo de
  /// `_DashboardPageState._visibleAccountsStream`.
  Stream<List<Account>> _visibleAccountsStream() {
    return Rx.combineLatest2<List<Account>, List<String>, List<Account>>(
      AccountService.instance.getAccounts(
        predicate: (acc, curr) => acc.closingDate.isNull(),
      ),
      HiddenModeService.instance.visibleAccountIdsStream,
      (accounts, visibleIds) {
        final visibleSet = visibleIds.toSet();
        return accounts
            .where((a) => visibleSet.contains(a.id))
            .toList(growable: false);
      },
    );
  }

  /// Espejo de `_DashboardPageState._perAccountConvertedStream`.
  Stream<double> _perAccountConvertedStream(
    Account account,
    String toCurrencyCode,
  ) {
    final balanceStream = AccountService.instance.getAccountMoney(
      account: account,
      convertToPreferredCurrency: false,
    );

    if (account.currency.code == toCurrencyCode) {
      return balanceStream;
    }

    final rateStream = ExchangeRateService.instance.calculateExchangeRate(
      fromCurrency: account.currency.code,
      toCurrency: toCurrencyCode,
      source: widget.rateSource,
    );

    return Rx.combineLatest2<double, double?, double>(
      balanceStream,
      rateStream,
      (balance, rate) => balance * (rate ?? 1),
    );
  }

  Stream<double> _getBalanceVariationStream() {
    return _visibleAccountsStream()
        .switchMap(
          (accounts) => AccountService.instance.getAccountsMoneyVariation(
            accounts: accounts,
            startDate: widget.dateRangeService.startDate,
            endDate: widget.dateRangeService.endDate,
            convertToPreferredCurrency: true,
          ),
        )
        .shareValue();
  }

  String get _preferredCurrencyCode =>
      widget.displayCurrency ??
      appStateSettings[SettingKey.preferredCurrency] ??
      'USD';

  Stream<double> _getTotalBalanceStream() {
    final preferredCurrencyCode = _preferredCurrencyCode;

    return _visibleAccountsStream().switchMap<double>((accounts) {
      if (accounts.isEmpty) return Stream<double>.value(0);

      final perAccountStreams = accounts
          .map((a) => _perAccountConvertedStream(a, preferredCurrencyCode))
          .toList();

      return Rx.combineLatestList<double>(perAccountStreams).map((values) {
        return values.fold<double>(0, (sum, value) => sum + value);
      });
    }).asBroadcastStream();
  }

  Stream<double> _getTotalBalanceInVesStream() {
    return _visibleAccountsStream().switchMap<double>((accounts) {
      if (accounts.isEmpty) return Stream<double>.value(0);

      final perAccountStreams = accounts
          .map((a) => _perAccountConvertedStream(a, 'VES'))
          .toList();

      return Rx.combineLatestList<double>(
        perAccountStreams,
      ).map((values) => values.fold<double>(0, (sum, v) => sum + v));
    }).asBroadcastStream();
  }

  Future<void> _togglePrivateModeValue({bool showSnackbar = false}) async {
    final privateMode =
        await PrivateModeService.instance.privateModeStream.first;

    await PrivateModeService.instance.setPrivateMode(!privateMode);

    await HapticFeedback.lightImpact();

    if (!mounted) return;

    if (showSnackbar) {
      WallexSnackbar.success(
        SnackbarParams(
          !privateMode
              ? t.settings.security.private_mode_activated
              : t.settings.security.private_mode_deactivated,
        ),
      );
    }
  }

  Widget _buildRateChip(BuildContext context, String source, String label) {
    final isSelected = widget.rateSource == source;
    return GestureDetector(
      onTap: () {
        if (widget.rateSource == source) return;
        widget.onRateSourceChanged(source);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: isSelected ? 0.4 : 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: Colors.white.withValues(alpha: isSelected ? 0.9 : 0.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final crossAxis = widget.alignStart
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final mainAxis = widget.alignStart
        ? MainAxisAlignment.start
        : MainAxisAlignment.center;

    return SuccessiveTapDetector(
      delayTrackingAfterGoal: 4000,
      onClickGoalReached: () => _togglePrivateModeValue(showSnackbar: true),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: crossAxis,
        spacing: 2,
        children: [
          Row(
            mainAxisAlignment: mainAxis,
            spacing: 4,
            children: [
              Text(
                t.home.total_balance,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              Tappable(
                bgColor: Colors.transparent,
                shape: const CircleBorder(),
                onTap: () => _togglePrivateModeValue(),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: StreamBuilder(
                    stream: PrivateModeService.instance.privateModeStream,
                    initialData: false,
                    builder: (context, snapshot) {
                      return Icon(
                        snapshot.data!
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.7),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          // ----- RATE SOURCE SELECTOR (BCV / Paralelo) -----
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: mainAxis,
            children: [
              _buildRateChip(context, 'bcv', 'BCV'),
              const SizedBox(width: 4),
              _buildRateChip(context, 'paralelo', 'Par'),
            ],
          ),

          // ----- PRIMARY BALANCE -----
          const SizedBox(height: 2),
          StreamBuilder(
            stream: _totalBalanceStream,
            builder: (context, snapshot) {
              return Skeletonizer(
                enabled: !snapshot.hasData,
                child: !snapshot.hasData
                    ? const Bone(width: 90, height: 40)
                    : Builder(
                        builder: (context) {
                          final double integerFontSize =
                              snapshot.data! >= 100000000 &&
                                      BreakPoint.of(
                                        context,
                                      ).isSmallerOrEqualTo(BreakpointID.xs)
                                  ? 32
                                  : 42;
                          return CurrencyDisplayer(
                            amountToConvert: snapshot.data!,
                            integerStyle: TextStyle(
                              fontSize: integerFontSize,
                              fontWeight: FontWeight.w200,
                              letterSpacing: -0.5,
                              color: Colors.white,
                            ),
                            currencyStyle: TextStyle(
                              fontSize: integerFontSize,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          );
                        },
                      ),
              );
            },
          ),

          // ----- SECONDARY EQUIVALENT (VES) -----
          const SizedBox(height: 2),
          StreamBuilder(
            stream: _totalBalanceInVesStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final formatted = snapshot.data!
                  .toStringAsFixed(2)
                  .replaceAllMapped(
                    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                    (m) => '${m[1]}.',
                  );
              return BlurBasedOnPrivateMode(
                child: Text(
                  '= $formatted Bs',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              );
            },
          ),

          //  ----- BALANCE TRENDING VALUE DURING THE SELECTED PERIOD -----
          if (widget.showDeltaPill &&
              widget.dateRangeService.startDate != null &&
              widget.dateRangeService.endDate != null)
            StreamBuilder(
              stream: _balanceVariationStream,
              builder: (context, snapshot) {
                return Skeletonizer(
                  enabled: !snapshot.hasData,
                  child: BalanceDeltaPill(percentage: snapshot.data ?? 0),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Registra el spec del widget `totalBalanceSummary`. Invocado desde
/// `registry_bootstrap.dart::registerDashboardWidgets`.
void registerTotalBalanceSummaryWidget() {
  DashboardWidgetRegistry.instance.register(
    DashboardWidgetSpec(
      type: WidgetType.totalBalanceSummary,
      displayName: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.total_balance_summary.name,
      description: (ctx) => Translations.of(
        ctx,
      ).home.dashboard_widgets.total_balance_summary.description,
      icon: Icons.account_balance_wallet_rounded,
      defaultSize: WidgetSize.fullWidth,
      allowedSizes: const <WidgetSize>{
        WidgetSize.medium,
        WidgetSize.fullWidth,
      },
      defaultConfig: const <String, dynamic>{
        'displayCurrency': null,
        'rateSource': null,
        'showDeltaPill': true,
      },
      recommendedFor: const <String>{
        'track_expenses',
        'save_usd',
        'reduce_debt',
        'budget',
      },
      builder: (context, descriptor, {required editing}) {
        // Wave 2 — render real. Lee el periodo / rateSource / refreshTick
        // del [DashboardScope] y `displayCurrency` / `showDeltaPill` del
        // descriptor.config (cae a `appStateSettings[preferredCurrency]`
        // cuando es `null`).
        final scope = DashboardScope.of(context);
        final cfgCurrency = descriptor.config['displayCurrency'];
        final cfgShowDelta = descriptor.config['showDeltaPill'];
        return KeyedSubtree(
          key: ValueKey('${descriptor.type.name}-${descriptor.instanceId}'),
          child: TotalBalanceSummaryWidget(
            dateRangeService: scope.dateRangeService,
            rateSource: scope.rateSource,
            onRateSourceChanged: scope.onRateSourceChanged,
            refreshTick: scope.refreshTick,
            displayCurrency: cfgCurrency is String ? cfgCurrency : null,
            showDeltaPill: cfgShowDelta is bool ? cfgShowDelta : true,
            // En el render dinámico el widget aparece como tarjeta dentro
            // del flujo, no en el header glass — usar el layout centrado
            // funciona mejor con `medium` / `fullWidth`.
            alignStart: false,
          ),
        );
      },
    ),
  );
}
