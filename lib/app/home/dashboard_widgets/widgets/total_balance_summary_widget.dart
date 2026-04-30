import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:kilatex/app/home/dashboard_widgets/dashboard_scope.dart';
import 'package:kilatex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:kilatex/app/home/dashboard_widgets/registry.dart';
import 'package:kilatex/app/home/widgets/balance_delta_pill.dart';
import 'package:kilatex/app/home/widgets/click_tracker.dart';
import 'package:kilatex/core/database/services/account/account_service.dart';
import 'package:kilatex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:kilatex/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:kilatex/core/database/services/user-setting/private_mode_service.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/models/account/account.dart';
import 'package:kilatex/core/models/currency/currency_display_policy.dart';
import 'package:kilatex/core/models/currency/currency_display_policy_resolver.dart';
import 'package:kilatex/core/models/date-utils/date_period_state.dart';
import 'package:kilatex/core/presentation/helpers/snackbar.dart';
import 'package:kilatex/core/presentation/responsive/breakpoints.dart';
import 'package:kilatex/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:kilatex/core/presentation/widgets/tappable.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';

/// Phase 6 of `currency-modes-rework`: the widget now derives its layout
/// from the [CurrencyDisplayPolicy] stream — for [SingleMode] it renders a
/// single primary line in `policy.code`; for [DualMode] it renders the
/// primary line in `policy.primary` plus a secondary equivalence line in
/// `policy.secondary`.
///
/// The BCV/Paralelo chip is gated by `policy.showsRateSourceChip` (true
/// only for the unordered `{USD, VES}` dual pair) so changing modes in
/// Settings hides/reveals the chip without an app reload.
///
/// `displayCurrency` constructor param is preserved for layout overrides
/// (the dashboard registry still wires it through `descriptor.config`),
/// but in practice the policy stream takes precedence — when null the
/// widget reads `policy.primary` (or `policy.code`).
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

  final DatePeriodState dateRangeService;

  /// Fuente de tasas activa (`'bcv'` o `'paralelo'`). El widget no la
  /// persiste por sí mismo — el padre la mantiene en su `State` y la
  /// reescribe en `SettingKey.preferredRateSource` al cambiarla.
  final String rateSource;

  /// Callback invocado cuando el usuario cambia la fuente de tasas vía los
  /// chips internos. El padre debe persistir y propagar el nuevo valor a
  /// otros widgets dependientes.
  final ValueChanged<String> onRateSourceChanged;

  /// Override opcional para el primary line. Cuando `null` se resuelve
  /// desde la policy stream (`policy.primary` o `policy.code`).
  final String? displayCurrency;

  final bool showDeltaPill;

  final bool alignStart;

  final int refreshTick;

  @override
  State<TotalBalanceSummaryWidget> createState() =>
      _TotalBalanceSummaryWidgetState();
}

class _TotalBalanceSummaryWidgetState extends State<TotalBalanceSummaryWidget> {
  Stream<double> _totalBalancePrimary = const Stream.empty();
  Stream<double> _totalBalanceSecondary = const Stream.empty();
  Stream<double> _balanceVariationStream = const Stream.empty();

  String? _primaryCurrencyCode;
  String? _secondaryCurrencyCode;

  @override
  void initState() {
    super.initState();
    _balanceVariationStream = _getBalanceVariationStream();
  }

  @override
  void didUpdateWidget(covariant TotalBalanceSummaryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rateSource != widget.rateSource ||
        oldWidget.dateRangeService.startDate !=
            widget.dateRangeService.startDate ||
        oldWidget.dateRangeService.endDate !=
            widget.dateRangeService.endDate ||
        oldWidget.displayCurrency != widget.displayCurrency ||
        oldWidget.refreshTick != widget.refreshTick) {
      _balanceVariationStream = _getBalanceVariationStream();
      // Streams keyed on currency code are rebuilt via _ensureStreams when
      // the policy stream re-emits below.
      if (_primaryCurrencyCode != null) {
        _totalBalancePrimary = _getTotalBalanceStreamFor(_primaryCurrencyCode!);
      }
      if (_secondaryCurrencyCode != null) {
        _totalBalanceSecondary =
            _getTotalBalanceStreamFor(_secondaryCurrencyCode!);
      }
    }
  }

  void _ensureStreams({required String primary, String? secondary}) {
    if (_primaryCurrencyCode != primary) {
      _primaryCurrencyCode = primary;
      _totalBalancePrimary = _getTotalBalanceStreamFor(primary);
    }
    if (_secondaryCurrencyCode != secondary) {
      _secondaryCurrencyCode = secondary;
      _totalBalanceSecondary = secondary == null
          ? const Stream.empty()
          : _getTotalBalanceStreamFor(secondary);
    }
  }

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

  /// Per-account converted stream — when the account is already in
  /// `toCurrencyCode` we pass the native balance through verbatim, so
  /// toggling the rate source NEVER affects the native portion of the
  /// total (the bug the rework absorbs).
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
      (balance, rate) => rate == null ? 0.0 : balance * rate,
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

  Stream<double> _getTotalBalanceStreamFor(String currencyCode) {
    return _visibleAccountsStream().switchMap<double>((accounts) {
      if (accounts.isEmpty) return Stream<double>.value(0);
      final perAccountStreams = accounts
          .map((a) => _perAccountConvertedStream(a, currencyCode))
          .toList();
      return Rx.combineLatestList<double>(perAccountStreams).map((values) {
        return values.fold<double>(0, (sum, value) => sum + value);
      });
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
      child: StreamBuilder<CurrencyDisplayPolicy>(
        stream: CurrencyDisplayPolicyResolver.instance.watch(),
        builder: (context, policySnap) {
          final policy = policySnap.data;

          // Resolve the primary / secondary currencies. The constructor
          // override (`displayCurrency`) wins for backward-compat with
          // the dashboard registry config.
          final String primary =
              widget.displayCurrency ??
              switch (policy) {
                SingleMode(:final code) => code,
                DualMode(:final primary) => primary,
                null => appStateSettings[SettingKey.preferredCurrency] ?? 'USD',
              };
          final String? secondary = switch (policy) {
            DualMode(:final secondary) => secondary,
            _ => null,
          };
          _ensureStreams(primary: primary, secondary: secondary);

          final showsChip = policy is DualMode && policy.showsRateSourceChip;

          return Column(
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
              // Phase 6.5/6.7: only render when the policy says so. This
              // covers the unordered USD+VES dual case AND removes the
              // chip from any single mode / non-VES dual mode.
              if (showsChip) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: mainAxis,
                  children: [
                    _buildRateChip(context, 'bcv', 'BCV'),
                    const SizedBox(width: 4),
                    _buildRateChip(context, 'paralelo', 'Par'),
                  ],
                ),
              ],

              // ----- PRIMARY BALANCE -----
              const SizedBox(height: 2),
              StreamBuilder(
                stream: _totalBalancePrimary,
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

              // ----- SECONDARY EQUIVALENCE -----
              // Phase 6.2: only render for DualMode. Single modes never
              // show a secondary equivalence (the chip is also hidden).
              if (policy is DualMode) ...[
                const SizedBox(height: 2),
                StreamBuilder(
                  stream: _totalBalanceSecondary,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    final formatted = snapshot.data!
                        .toStringAsFixed(2)
                        .replaceAllMapped(
                          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                          (m) => '${m[1]}.',
                        );
                    final symbol = policy.secondary == 'VES'
                        ? 'Bs'
                        : policy.secondary;
                    return BlurBasedOnPrivateMode(
                      child: Text(
                        '= $formatted $symbol',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    );
                  },
                ),
              ],

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
          );
        },
      ),
    );
  }
}

/// Registra el spec del widget `totalBalanceSummary`.
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
            alignStart: false,
          ),
        );
      },
    ),
  );
}
