import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallex/app/home/widgets/click_tracker.dart';
import 'package:wallex/app/home/widgets/dashboard_cards.dart';
import 'package:wallex/app/home/widgets/horizontal_scrollable_account_list.dart';
import 'package:wallex/app/home/widgets/income_or_expense_card.dart';
import 'package:wallex/app/home/widgets/new_transaction_fl_button.dart';

import 'package:wallex/app/layout/page_context.dart';
import 'package:wallex/app/layout/page_framework.dart';
import 'package:wallex/app/settings/widgets/edit_profile_modal.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/services/dolar_api_service.dart';
import 'package:wallex/core/database/services/user-setting/private_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/extensions/color.extensions.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/core/presentation/animations/animated_expanded.dart';
import 'package:wallex/core/presentation/debug_page.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/presentation/responsive/breakpoints.dart';
import 'package:wallex/core/presentation/theme.dart';
import 'package:wallex/core/presentation/widgets/dates/date_period_modal.dart';
import 'package:wallex/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:wallex/core/presentation/widgets/tappable.dart';
import 'package:wallex/core/presentation/widgets/trending_value.dart';
import 'package:wallex/core/presentation/widgets/user_avatar.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/utils/app_utils.dart';
import 'package:wallex/i18n/generated/translations.g.dart';
import 'package:rxdart/rxdart.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../core/models/transaction/transaction_type.enum.dart';
import '../../core/presentation/app_colors.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DatePeriodState dateRangeService = const DatePeriodState();
  final ScrollController _scrollController = ScrollController();

  late Stream<double> _balanceVariationStream;
  late Stream<double> _totalBalanceStream;

  String _rateSource = 'bcv';
  late Stream<double> _totalBalanceInVesStream;

  @override
  void initState() {
    super.initState();

    _balanceVariationStream = _getBalanceVariationStream();

    _totalBalanceStream = _getTotalBalanceStream();
    _totalBalanceInVesStream = _getTotalBalanceInVesStream();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Stream<double> _getBalanceVariationStream() {
    return AccountService.instance
        .getAccounts(predicate: (acc, curr) => acc.closingDate.isNull())
        .switchMap(
      (accounts) => AccountService.instance.getAccountsMoneyVariation(
        accounts: accounts,
        startDate: dateRangeService.startDate,
        endDate: dateRangeService.endDate,
        convertToPreferredCurrency: true,
      ),
    );
  }

  Stream<double> _getTotalBalanceStream() {
    return AccountService.instance
        .getAccounts(predicate: (acc, curr) => acc.closingDate.isNull())
        .switchMap((accounts) {
      if (accounts.isEmpty) return Stream.value(0);

      final accountMoneyStreams = accounts
          .map(
            (account) => AccountService.instance.getAccountMoney(
              account: account,
              convertToPreferredCurrency: false,
            ),
          )
          .toList();

      final preferredCurrencyCode =
          appStateSettings[SettingKey.preferredCurrency] ?? 'USD';

      return Rx.combineLatestList<double>(accountMoneyStreams).switchMap(
        (balances) {
          final convertedStreams = List.generate(accounts.length, (i) {
            final account = accounts[i];
            final balance = i < balances.length ? balances[i] : 0.0;

            if (account.currency.code == preferredCurrencyCode) {
              return Stream.value(balance);
            }

            return ExchangeRateService.instance
                .calculateExchangeRate(
                  fromCurrency: account.currency.code,
                  toCurrency: preferredCurrencyCode,
                  amount: balance,
                  source: _rateSource,
                )
                .map((v) => v ?? 0);
          });

          return Rx.combineLatestList<double>(convertedStreams).map((values) {
            final total = values.fold<double>(0, (sum, value) => sum + value);

            if (kDebugMode) {
              final details = List.generate(accounts.length, (i) {
                final account = accounts[i];
                final rawBalance = i < balances.length ? balances[i] : 0.0;
                final converted = i < values.length ? values[i] : 0.0;
                return '${account.name}: ${rawBalance.toStringAsFixed(2)} ${account.currency.code} -> ${converted.toStringAsFixed(2)} $preferredCurrencyCode';
              }).join(' | ');

              debugPrint(
                'Dashboard total debug -> total=${total.toStringAsFixed(2)} $preferredCurrencyCode | $details',
              );
            }

            return total;
          });
        },
      );
    });
  }

  Stream<double> _getTotalBalanceInVesStream() {
    return AccountService.instance
        .getAccounts(predicate: (acc, curr) => acc.closingDate.isNull())
        .switchMap((accounts) {
      if (accounts.isEmpty) return Stream.value(0);

      final accountMoneyStreams = accounts
          .map((account) => AccountService.instance.getAccountMoney(
                account: account,
                convertToPreferredCurrency: false,
              ))
          .toList();

      return Rx.combineLatestList<double>(accountMoneyStreams).switchMap(
        (balances) {
          final convertedStreams = List.generate(accounts.length, (i) {
            final account = accounts[i];
            final balance = i < balances.length ? balances[i] : 0.0;

            if (account.currency.code == 'VES') {
              return Stream.value(balance);
            }

            return ExchangeRateService.instance
                .calculateExchangeRate(
                  fromCurrency: account.currency.code,
                  toCurrency: 'VES',
                  amount: balance,
                  source: _rateSource,
                )
                .map((v) => v ?? 0);
          });

          return Rx.combineLatestList<double>(convertedStreams)
              .map((values) => values.fold<double>(0, (sum, v) => sum + v));
        },
      );
    });
  }

  bool _isIncomeExpenseAtSameLevel(BuildContext context) {
    return BreakPoint.of(context).isLargerOrEqualTo(BreakpointID.sm);
  }

  /// Refresh data streams when user pulls down
  Future<void> _refreshData() async {
    setState(() {
      _balanceVariationStream = _getBalanceVariationStream();
      _totalBalanceStream = _getTotalBalanceStream();
      _totalBalanceInVesStream = _getTotalBalanceInVesStream();
    });
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    final accountService = AccountService.instance;

    return PageFramework(
      title: t.home.title,
      enableAppBar: false,
      appBarBackgroundColor:
          BreakPoint.of(context).isLargerOrEqualTo(BreakpointID.md)
          ? Colors.transparent
          : AppColors.of(context).consistentPrimary,
      floatingActionButton: ifIsInTabs(context)
          ? null
          : NewTransactionButton(
              key: const Key('dashboard--new-transaction-button'),
              scrollController: _scrollController,
            ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 80),
          child: Column(
            children: [
              // ── Big header (scrolls away naturally) ──
              buildDashboadHeader(context, accountService),

              HorizontalScrollableAccountList(
                dateRangeService: dateRangeService,
              ),

              // ── Exchange Rates Card ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: _buildRatesCard(context),
              ),

              // ── Stats Cards ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DashboardCards(dateRangeService: dateRangeService),
              ),

              if (kDebugMode)
                TextButton(
                  onPressed: () {
                    RouteUtils.pushRoute(const DebugPage());
                  },
                  child: const Text('DEBUG PAGE'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildDashboadHeader(
    BuildContext context,
    AccountService accountService,
  ) {
    final shouldHavePadding =
        !AppUtils.isDesktop && !AppUtils.isMobileLayout(context);

    return SkeletonizerConfig(
      data: _getSkeletonizerConfig(context),
      child: Card(
        color: AppColors.of(context).consistentPrimary,
        margin: EdgeInsets.only(
          bottom: 0,
          top: shouldHavePadding ? 8 : 0,
          left: shouldHavePadding ? 12 : 0,
          right: shouldHavePadding ? 12 : 0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(getCardBorderRadius()),
            top: Radius.circular(shouldHavePadding ? getCardBorderRadius() : 0),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _isIncomeExpenseAtSameLevel(context) ? 24 : 16,
            16,
            _isIncomeExpenseAtSameLevel(context) ? 24 : 16,
            _isIncomeExpenseAtSameLevel(context) ? 24 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: buildWelcomeMsgAndAvatar(context)),
                  buildDatePeriodSelector(context),
                ],
              ),
              Divider(
                height: 16,
                color: AppColors.of(
                  context,
                ).onConsistentPrimary.withOpacity(0.5),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final labelStyle = Theme.of(context).textTheme.labelMedium!
                      .copyWith(color: onHeaderSmallTextColor(context));

                  final incomeAndExpenseCards = [
                    IncomeOrExpenseCard(
                      type: TransactionType.expense,
                      periodState: dateRangeService,
                      labelStyle: labelStyle,
                      rateSource: _rateSource,
                    ),
                    IncomeOrExpenseCard(
                      type: TransactionType.income,
                      periodState: dateRangeService,
                      labelStyle: labelStyle,
                      rateSource: _rateSource,
                    ),
                  ];

                  if (_isIncomeExpenseAtSameLevel(context)) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      spacing: 16,
                      children: [
                        totalBalanceIndicator(context),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: incomeAndExpenseCards,
                        ),
                      ],
                    );
                  }

                  return Column(
                    spacing: 24,
                    children: [
                      totalBalanceIndicator(context),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: incomeAndExpenseCards,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  ActionChip buildDatePeriodSelector(BuildContext context) {
    return ActionChip(
      label: Text(
        dateRangeService.getText(
          context,
          showLongMonth: MediaQuery.of(context).size.width > 360,
        ),
        style: TextStyle(color: AppColors.of(context).onConsistentPrimary),
      ),
      backgroundColor: AppColors.of(context).consistentPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          //   style: BorderStyle.none,
          color: AppColors.of(context).onConsistentPrimary,
        ),
      ),
      onPressed: () {
        openDatePeriodModal(
          context,
          DatePeriodModal(initialDatePeriod: dateRangeService.datePeriod),
        ).then((value) {
          if (value == null) return;

          setState(() {
            dateRangeService = dateRangeService.copyWith(
              periodModifier: 0,
              datePeriod: value,
            );

            _balanceVariationStream = _getBalanceVariationStream();
          });
        });
      },
    );
  }

  Tappable buildWelcomeMsgAndAvatar(BuildContext context) {
    return Tappable(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) {
            return const EditProfileModal();
          },
        );
      },
      bgColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 24, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            UserAvatar(
              avatar: appStateSettings[SettingKey.avatar],
              backgroundColor: AppColors.of(
                context,
              ).onConsistentPrimary.darken(0.25),
              border: Border.all(
                width: 2,
                color: AppColors.of(context).onConsistentPrimary,
              ),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Welcome again!",
                    softWrap: false,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      overflow: TextOverflow.fade,
                      color: onHeaderSmallTextColor(context),
                    ),
                  ),
                  Text(
                    appStateSettings[SettingKey.userName] ?? 'User',
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      fontSize: 18,
                      overflow: TextOverflow.fade,
                      color: AppColors.of(context).onConsistentPrimary,
                    ),
                  ),

                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSmallHeader(BuildContext context) {
    return SkeletonizerConfig(
      data: _getSkeletonizerConfig(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          color: AppColors.of(context).consistentPrimary,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.home.total_balance,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: onHeaderSmallTextColor(context),
                  ),
                ),
                StreamBuilder(
                  stream: _totalBalanceStream,
                  builder: (context, snapshot) {
                    return Skeletonizer(
                      enabled: !snapshot.hasData,
                      child: Builder(
                        builder: (context) {
                          if (!snapshot.hasData) {
                            return Text('9999', style: TextStyle(fontSize: 22));
                          }

                          return CurrencyDisplayer(
                            amountToConvert: snapshot.data!,
                            integerStyle: TextStyle(
                              fontSize:
                                  snapshot.data! >= 10000000 &&
                                      BreakPoint.of(
                                        context,
                                      ).isSmallerOrEqualTo(BreakpointID.xs)
                                  ? 22
                                  : 26,
                              fontWeight: FontWeight.bold,
                              color: AppColors.of(context).onConsistentPrimary,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(width: 12),
            Flexible(child: buildDatePeriodSelector(context)),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePrivateModeValue({bool showSnackbar = false}) async {
    final privateMode =
        await PrivateModeService.instance.privateModeStream.first;

    PrivateModeService.instance.setPrivateMode(!privateMode);

    await HapticFeedback.lightImpact();

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

  Widget totalBalanceIndicator(BuildContext context) {
    final t = Translations.of(context);

    return SuccessiveTapDetector(
      delayTrackingAfterGoal: 4000,
      onClickGoalReached: () => _togglePrivateModeValue(showSnackbar: true),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: _isIncomeExpenseAtSameLevel(context)
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        spacing: 2,
        children: [
          Row(
            mainAxisAlignment: _isIncomeExpenseAtSameLevel(context)
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            spacing: 4,
            children: [
              Text(
                t.home.total_balance,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: onHeaderSmallTextColor(context),
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
                        color: onHeaderSmallTextColor(context),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          // ----- CURRENT BALANCE AMOUNT HEADER -----
          StreamBuilder(
            stream: _totalBalanceStream,
            builder: (context, snapshot) {
              return Skeletonizer(
                enabled: !snapshot.hasData,
                child: !snapshot.hasData
                    ? Bone(width: 90, height: 40)
                    : CurrencyDisplayer(
                        amountToConvert: snapshot.data!,
                        integerStyle: Theme.of(context).textTheme.headlineLarge!
                            .copyWith(
                              fontSize:
                                  snapshot.data! >= 100000000 &&
                                      BreakPoint.of(
                                        context,
                                      ).isSmallerOrEqualTo(BreakpointID.xs)
                                  ? 26
                                  : 32,
                              fontWeight: FontWeight.bold,
                              color: AppColors.of(context).onConsistentPrimary,
                            ),
                      ),
              );
            },
          ),

          // ----- RATE SOURCE TOGGLE -----
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: _isIncomeExpenseAtSameLevel(context)
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              _buildRateChip(context, 'bcv', 'BCV'),
              const SizedBox(width: 8),
              _buildRateChip(context, 'paralelo', 'Paralelo'),
            ],
          ),

          // ----- VES EQUIVALENT -----
          const SizedBox(height: 2),
          StreamBuilder(
            stream: _totalBalanceInVesStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final vesTotal = snapshot.data!;
              final formatted = vesTotal.toStringAsFixed(2).replaceAllMapped(
                RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
                (m) => '${m[1]}.',
              );
              return BlurBasedOnPrivateMode(
                child: Text(
                  '= $formatted Bs',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: onHeaderSmallTextColor(context),
                    fontSize: 13,
                  ),
                ),
              );
            },
          ),

          //  ----- BALANCE TRENDING VALUE DURING THE SELECTED PERIOD -----
          if (dateRangeService.startDate != null &&
              dateRangeService.endDate != null)
            StreamBuilder(
              stream: _balanceVariationStream,
              builder: (context, snapshot) {
                return Skeletonizer(
                  enabled: !snapshot.hasData,
                  child: TrendingValue(
                    percentage: snapshot.data ?? 0,
                    fontWeight: FontWeight.bold,
                    filled: true,
                    outlined: true,
                    fontSize: 16,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRateChip(BuildContext context, String source, String label) {
    final isSelected = _rateSource == source;
    return GestureDetector(
      onTap: () {
        if (_rateSource == source) return;
        setState(() {
          _rateSource = source;
          _totalBalanceStream = _getTotalBalanceStream();
          _totalBalanceInVesStream = _getTotalBalanceInVesStream();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.of(context).onConsistentPrimary.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.of(context).onConsistentPrimary.withOpacity(
              isSelected ? 0.6 : 0.3,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: AppColors.of(context).onConsistentPrimary.withOpacity(
              isSelected ? 1.0 : 0.6,
            ),
          ),
        ),
      ),
    );
  }

  /// Fetches rates from DolarApiService (API call with cache)
  /// and displays them in a table. Falls back to DB rates if API fails.
  Widget _buildRatesCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.currency_exchange, size: 18,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Tasas de cambio',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder(
              future: _fetchRatesForDisplay(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final data = snapshot.data;
                final usdBcv = data?['usdBcv'];
                final usdPar = data?['usdPar'];
                final eurBcv = data?['eurBcv'];
                final eurPar = data?['eurPar'];

                final usdAvg = (usdBcv != null && usdPar != null)
                    ? (usdBcv + usdPar) / 2
                    : null;
                final eurAvg = (eurBcv != null && eurPar != null)
                    ? (eurBcv + eurPar) / 2
                    : null;

                return Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.2),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(1),
                  },
                  children: [
                    _rateTableHeader(context),
                    _rateTableRow(context, '\$ USD', usdBcv, usdPar, usdAvg),
                    _rateTableRow(context, '€ EUR', eurBcv, eurPar, eurAvg),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, double?>> _fetchRatesForDisplay() async {
    final api = DolarApiService.instance;

    // Use cached values if fresh, otherwise fetch
    if (api.isStale) {
      await api.fetchAll();
    }

    // EUR rates may fail due to API rate-limiting after multiple calls.
    // Retry EUR specifically if missing.
    if (api.eurOficialRate == null || api.eurParaleloRate == null) {
      await api.fetchAllEurRates();
    }

    return {
      'usdBcv': api.oficialRate?.promedio,
      'usdPar': api.paraleloRate?.promedio,
      'eurBcv': api.eurOficialRate?.promedio,
      'eurPar': api.eurParaleloRate?.promedio,
    };
  }

  TableRow _rateTableHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
    );
    return TableRow(
      children: [
        const SizedBox(height: 24),
        Center(child: Text('BCV', style: style)),
        Center(child: Text('Paralelo', style: style)),
        Center(child: Text('Promedio', style: style)),
      ],
    );
  }

  TableRow _rateTableRow(
    BuildContext context,
    String label,
    double? bcv,
    double? paralelo,
    double? avg,
  ) {
    final labelStyle = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontWeight: FontWeight.w600,
    );
    final valueStyle = Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFeatures: [const FontFeature.tabularFigures()],
    );

    String fmt(double? v) => v != null ? v.toStringAsFixed(2) : '--';

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, style: labelStyle),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(fmt(bcv), style: valueStyle),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(fmt(paralelo), style: valueStyle),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              fmt(avg),
              style: valueStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  SkeletonizerConfigData _getSkeletonizerConfig(BuildContext context) {
    return SkeletonizerConfigData(
      effect: ShimmerEffect(
        baseColor: AppColors.of(context).onConsistentPrimary.withOpacity(0.1),
        highlightColor: AppColors.of(
          context,
        ).onConsistentPrimary.withOpacity(0.25),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

Color onHeaderSmallTextColor(BuildContext context) =>
    // ignore: deprecated_member_use
    AppColors.of(context).onConsistentPrimary.withOpacity(0.9);
