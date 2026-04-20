import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:wallex/app/common/widgets/user_avatar_display.dart';
import 'package:wallex/app/home/widgets/click_tracker.dart';
import 'package:wallex/app/home/widgets/dashboard_cards.dart';
import 'package:wallex/app/home/widgets/horizontal_scrollable_account_list.dart';
import 'package:wallex/app/home/widgets/income_or_expense_card.dart';
import 'package:wallex/app/home/widgets/new_transaction_fl_button.dart';

import 'package:wallex/app/layout/page_context.dart';
import 'package:wallex/app/layout/page_framework.dart';
import 'package:wallex/app/settings/widgets/edit_profile_modal.dart';
import 'package:wallex/app/settings/widgets/pin_modal.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:wallex/core/database/services/account/account_service.dart';
import 'package:wallex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:wallex/core/services/dolar_api_service.dart';
import 'package:wallex/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/private_mode_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/account/account.dart';
import 'package:wallex/core/models/date-utils/date_period.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/core/models/date-utils/period_type.dart';
import 'package:wallex/core/presentation/debug_page.dart';
import 'package:wallex/core/presentation/helpers/snackbar.dart';
import 'package:wallex/core/presentation/responsive/breakpoints.dart';
import 'package:wallex/core/presentation/theme.dart';
import 'package:wallex/core/presentation/widgets/dates/date_period_modal.dart';
import 'package:wallex/core/presentation/widgets/number_ui_formatters/currency_displayer.dart';
import 'package:wallex/core/presentation/widgets/tappable.dart';
import 'package:wallex/core/presentation/widgets/trending_value.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/utils/app_utils.dart';
import 'package:wallex/i18n/generated/translations.g.dart';
import 'package:rxdart/rxdart.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../core/models/transaction/transaction_type.enum.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DatePeriodState dateRangeService = const DatePeriodState();
  final ScrollController _scrollController = ScrollController();
  bool _glassReady = false;

  late Stream<double> _balanceVariationStream;
  late Stream<double> _totalBalanceStream;

  String _rateSource = 'bcv';
  late Stream<double> _totalBalanceInVesStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _glassReady = true);
    });

    _balanceVariationStream = _getBalanceVariationStream();

    _totalBalanceStream = _getTotalBalanceStream();
    _totalBalanceInVesStream = _getTotalBalanceInVesStream();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Combines the base account stream with [HiddenModeService.visibleAccountIdsStream]
  /// so every derived balance on the dashboard silently excludes saving
  /// accounts while Hidden Mode is locked. When the feature is disabled the
  /// visibility stream emits every id, so the filter is a no-op.
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

  Stream<double> _getBalanceVariationStream() {
    return _visibleAccountsStream()
        .switchMap(
          (accounts) => AccountService.instance.getAccountsMoneyVariation(
            accounts: accounts,
            startDate: dateRangeService.startDate,
            endDate: dateRangeService.endDate,
            convertToPreferredCurrency: true,
          ),
        )
        .shareValue();
  }

  Stream<double> _getTotalBalanceStream() {
    return _visibleAccountsStream().switchMap<double>((accounts) {
          if (accounts.isEmpty) return Stream<double>.value(0);

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

          return Rx.combineLatestList<double>(accountMoneyStreams).switchMap((
            balances,
          ) {
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
          });
        }).asBroadcastStream();
  }

  Stream<double> _getTotalBalanceInVesStream() {
    return _visibleAccountsStream().switchMap<double>((accounts) {
          if (accounts.isEmpty) return Stream<double>.value(0);

          final accountMoneyStreams = accounts
              .map(
                (account) => AccountService.instance.getAccountMoney(
                  account: account,
                  convertToPreferredCurrency: false,
                ),
              )
              .toList();

          return Rx.combineLatestList<double>(accountMoneyStreams).switchMap((
            balances,
          ) {
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

            return Rx.combineLatestList<double>(
              convertedStreams,
            ).map((values) => values.fold<double>(0, (sum, v) => sum + v));
          });
        }).asBroadcastStream();
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
      appBarBackgroundColor: Colors.transparent,
      floatingActionButton: ifIsInTabs(context)
          ? null
          : NewTransactionButton(
              key: const Key('dashboard--new-transaction-button'),
              scrollController: _scrollController,
            ),
      floatingActionButtonLocation: ExpandableFab.location,
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

              // Visibility-aware carousel: while Hidden Mode is locked the
              // stream omits savings account ids, so the carousel hides them
              // without having to know anything about the feature.
              StreamBuilder<List<String>>(
                stream: HiddenModeService.instance.visibleAccountIdsStream,
                builder: (context, snapshot) {
                  return HorizontalScrollableAccountList(
                    dateRangeService: dateRangeService,
                    visibleAccountIds: snapshot.data,
                  );
                },
              ),

              // ── Exchange Rates Card ──
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
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

  /// Wraps [child] in a glass container. On the first frame, renders a solid
  /// fallback (no BackdropFilter) to avoid the expensive blur during cold
  /// start. After the first frame, [_glassReady] flips to true and the real
  /// BackdropFilter is used.
  Widget _headerContainer({
    required BorderRadius borderRadius,
    required Widget child,
  }) {
    return Builder(
      builder: (context) {
        final glassTint = Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.15);
        final glassBorder = Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.1);

        final container = DecoratedBox(
          decoration: BoxDecoration(
            color: glassTint,
            borderRadius: borderRadius,
            border: Border.all(color: glassBorder, width: 1),
          ),
          child: child,
        );

        if (_glassReady) {
          return ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: container,
            ),
          );
        }

        return container;
      },
    );
  }

  Widget buildDashboadHeader(
    BuildContext context,
    AccountService accountService,
  ) {
    final shouldHavePadding =
        !AppUtils.isDesktop && !AppUtils.isMobileLayout(context);

    final headerBorderRadius = BorderRadius.vertical(
      bottom: Radius.circular(getCardBorderRadius()),
      top: Radius.circular(shouldHavePadding ? getCardBorderRadius() : 0),
    );

    return SkeletonizerConfig(
      data: _getSkeletonizerConfig(context),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 0,
          top: shouldHavePadding ? 8 : 0,
          left: shouldHavePadding ? 12 : 0,
          right: shouldHavePadding ? 12 : 0,
        ),
        child: _headerContainer(
          borderRadius: headerBorderRadius,
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
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<String>>(
                  stream: HiddenModeService.instance.visibleAccountIdsStream,
                  builder: (context, snapshot) {
                    final labelStyle = Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: Colors.white.withValues(alpha: 0.7));

                    // While Hidden Mode is locked this list excludes savings
                    // account ids, so the income/expense totals are computed
                    // without their transactions. When null (first frame)
                    // fall back to unfiltered totals; the stream immediately
                    // emits and re-renders.
                    final visibleIds = snapshot.data;
                    final accountFilter = visibleIds == null
                        ? null
                        : TransactionFilterSet(accountsIDs: visibleIds);

                    final incomeAndExpenseCards = [
                      IncomeOrExpenseCard(
                        type: TransactionType.expense,
                        periodState: dateRangeService,
                        labelStyle: labelStyle,
                        rateSource: _rateSource,
                        filters: accountFilter,
                      ),
                      IncomeOrExpenseCard(
                        type: TransactionType.income,
                        periodState: dateRangeService,
                        labelStyle: labelStyle,
                        rateSource: _rateSource,
                        filters: accountFilter,
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
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      onPressed: () {
        // Hidden Mode restricts the period picker to bounded ranges so the
        // user cannot peek at savings-era data through an "all time" query
        // while the app is locked. See HiddenModeService.
        final isLocked = HiddenModeService.instance.isLocked;
        final allowedTypes = isLocked
            ? const [PeriodType.cycle, PeriodType.lastDays]
            : null;

        // Edge case: if the current state holds a PeriodType that is no
        // longer allowed (because the mode was just locked), coerce it to
        // `cycle` before opening the modal so the sheet doesn't highlight
        // a hidden option.
        final currentType = dateRangeService.datePeriod.periodType;
        if (isLocked &&
            (currentType == PeriodType.allTime ||
                currentType == PeriodType.dateRange)) {
          setState(() {
            dateRangeService = dateRangeService.copyWith(
              periodModifier: 0,
              datePeriod: const DatePeriod(periodType: PeriodType.cycle),
            );
            _balanceVariationStream = _getBalanceVariationStream();
          });
        }

        openDatePeriodModal(
          context,
          DatePeriodModal(
            initialDatePeriod: dateRangeService.datePeriod,
            allowedTypes: allowedTypes,
          ),
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
            // Long-press on the avatar opens the unlock PIN modal when
            // Hidden Mode is enabled and currently locked. Short taps
            // propagate to the surrounding Tappable (edit-profile sheet).
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: _handleSecretTap,
              child: UserAvatarDisplay(
                avatar: appStateSettings[SettingKey.avatar],
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                border: Border.all(
                  width: 2,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Welcome again!',
                    softWrap: false,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      overflow: TextOverflow.fade,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    appStateSettings[SettingKey.userName] ?? 'User',
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      fontSize: 18,
                      overflow: TextOverflow.fade,
                      color: Colors.white,
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
    const smallHeaderRadius = BorderRadius.only(
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    );

    return SkeletonizerConfig(
      data: _getSkeletonizerConfig(context),
      child: _headerContainer(
        borderRadius: smallHeaderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                      color: Colors.white.withValues(alpha: 0.7),
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
                              return Text(
                                '9999',
                                style: TextStyle(fontSize: 22),
                              );
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
                                    : 28,
                                fontWeight: FontWeight.w200,
                                letterSpacing: -0.5,
                                color: Colors.white,
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
      ),
    );
  }

  /// Secret 6-tap handler wired to the avatar. Silently no-ops when Hidden
  /// Mode is disabled or already unlocked so users who don't have the
  /// feature never see the PIN modal.
  Future<void> _handleSecretTap() async {
    final enabled = await HiddenModeService.instance.isEnabled();
    if (!enabled) return;
    if (!HiddenModeService.instance.isLocked) return;
    if (!mounted) return;
    final ok = await showUnlockPinModal(context);
    if (!mounted) return;
    if (ok) {
      final pinT = Translations.of(context).settings.hidden_mode.pin;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pinT.unlocked),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
            mainAxisAlignment: _isIncomeExpenseAtSameLevel(context)
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              _buildRateChip(context, 'bcv', 'BCV'),
              const SizedBox(width: 4),
              _buildRateChip(context, 'paralelo', 'Par'),
            ],
          ),

          // ----- PRIMARY BALANCE (USD) -----
          const SizedBox(height: 2),
          StreamBuilder(
            stream: _totalBalanceStream,
            builder: (context, snapshot) {
              return Skeletonizer(
                enabled: !snapshot.hasData,
                child: !snapshot.hasData
                    ? Bone(width: 90, height: 40)
                    : CurrencyDisplayer(
                        amountToConvert: snapshot.data!,
                        integerStyle: TextStyle(
                          fontSize:
                              snapshot.data! >= 100000000 &&
                                  BreakPoint.of(
                                    context,
                                  ).isSmallerOrEqualTo(BreakpointID.xs)
                              ? 32
                              : 42,
                          fontWeight: FontWeight.w200,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
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
        // Persist globally so transaction-service streams (used by Gasto/
        // Ingreso cards) requery with the new rate source. setItem updates
        // appStateSettings synchronously, so the following setState rebuild
        // picks up the new value when recreating the StreamBuilders.
        UserSettingService.instance.setItem(
          SettingKey.preferredRateSource,
          source,
        );
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

  /// Fetches rates from DolarApiService (API call with cache)
  /// and displays them in a table. Falls back to DB rates if API fails.
  Widget _buildRatesCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final cardContent = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_exchange, size: 18, color: primary),
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
    );

    if (isDark) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
          child: cardContent,
        ),
      );
    } else {
      return Card(child: cardContent);
    }
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
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600);
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
        baseColor: Colors.white.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.2),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

Color onHeaderSmallTextColor(BuildContext context) =>
    Colors.white.withValues(alpha: 0.7);
