import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:bolsio/app/common/widgets/user_avatar_display.dart';
import 'package:bolsio/app/home/dashboard_widgets/dashboard_layout_body.dart';
import 'package:bolsio/app/home/dashboard_widgets/dashboard_scope.dart';
import 'package:bolsio/app/home/dashboard_widgets/defaults.dart';
import 'package:bolsio/app/home/dashboard_widgets/edit/add_widget_sheet.dart';
import 'package:bolsio/app/home/dashboard_widgets/edit/editable_widget_frame.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/dashboard_layout.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/registry.dart';
import 'package:bolsio/app/home/dashboard_widgets/services/dashboard_layout_service.dart';
import 'package:bolsio/app/home/dashboard_widgets/widgets/total_balance_summary_widget.dart';
import 'package:bolsio/app/home/widgets/income_or_expense_card.dart';
import 'package:bolsio/app/home/widgets/new_transaction_fl_button.dart';

import 'package:bolsio/app/layout/page_context.dart';
import 'package:bolsio/app/layout/page_framework.dart';
import 'package:bolsio/app/settings/widgets/edit_profile_modal.dart';
import 'package:bolsio/app/settings/widgets/pin_modal.dart';
import 'package:bolsio/core/database/services/account/account_service.dart';
import 'package:bolsio/core/database/services/app-data/app_data_service.dart';
import 'package:bolsio/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/models/currency/currency_display_policy.dart';
import 'package:bolsio/core/models/currency/currency_display_policy_resolver.dart';
import 'package:bolsio/core/models/date-utils/date_period.dart';
import 'package:bolsio/core/models/date-utils/date_period_state.dart';
import 'package:bolsio/core/models/date-utils/period_type.dart';
import 'package:bolsio/core/services/rate_providers/rate_refresh_service.dart';
import 'package:bolsio/core/presentation/app_colors.dart';
import 'package:bolsio/core/presentation/debug_page.dart';
import 'package:bolsio/core/presentation/responsive/breakpoints.dart';
import 'package:bolsio/core/presentation/theme.dart';
import 'package:bolsio/core/presentation/widgets/dates/date_period_modal.dart';
import 'package:bolsio/core/presentation/widgets/tappable.dart';
import 'package:bolsio/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/core/utils/app_utils.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../core/models/transaction/transaction_type.enum.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  DatePeriodState dateRangeService = const DatePeriodState();
  final ScrollController _scrollController = ScrollController();
  bool _glassReady = false;

  /// Toggle local de edit mode. Cuando es `true`, el body se reemplaza por
  /// un `ReorderableListView` con los widgets envueltos en
  /// `EditableWidgetFrame`. Spec `dashboard-edit-mode` § Toggle.
  bool _editing = false;

  String _rateSource = 'bcv';

  /// Phase 6.8 of `currency-modes-rework`: subscribe to the persisted
  /// `preferredRateSource` setting so external mutations (Settings page,
  /// onboarding rerun, Firebase sync) propagate to the dashboard without
  /// a manual reload. The subscription is cancelled in [dispose].
  StreamSubscription<String?>? _rateSourceSubscription;

  /// Phase 6.5/6.8: subscribe to the policy stream so the dashboard
  /// rebuilds (and downstream descendant widgets re-derive their layout)
  /// the moment the user switches modes from Settings — without forcing
  /// a manual reload. The actual policy value is consumed by self-
  /// subscribed widgets like [TotalBalanceSummaryWidget] (chip gating)
  /// and [IncomeOrExpenseCard] (single vs dual layout).
  StreamSubscription<CurrencyDisplayPolicy>? _policySubscription;

  /// Counter incremented on pull-to-refresh so descendant widgets that cache
  /// streams in `initState` (`TotalBalanceSummaryWidget`, etc.) see a changed
  /// prop in `didUpdateWidget` and re-subscribe.
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _glassReady = true);
    });

    // Initialize the rate source from the persisted setting so multiple
    // tabs / sessions agree on the same value.
    final persisted = appStateSettings[SettingKey.preferredRateSource];
    if (persisted == 'bcv' || persisted == 'paralelo') {
      _rateSource = persisted!;
    }

    // Phase 6.8 — listen for external mutations to `preferredRateSource`
    // (Settings page, onboarding rerun, Firebase sync) so the dashboard
    // stays consistent without a manual reload.
    _rateSourceSubscription = UserSettingService.instance
        .getSettingFromDB(SettingKey.preferredRateSource)
        .listen((value) {
      if (!mounted) return;
      if (value == 'bcv' || value == 'paralelo') {
        if (_rateSource != value) setState(() => _rateSource = value!);
      }
    });

    // Phase 6.5/6.8 — drive a rebuild whenever the policy changes so
    // descendant widgets (which subscribe to the same stream
    // independently) get a fresh frame in step with the chip's new
    // gating. We don't need to retain the value locally — the
    // descendants own the state.
    _policySubscription = CurrencyDisplayPolicyResolver.instance
        .watch()
        .listen((_) {
      if (!mounted) return;
      setState(() {});
    });

    // Kick off the layout load + fallback gate. This is fire-and-forget —
    // the StreamBuilder downstream observes the BehaviorSubject directly,
    // so the first frame renders an empty list and the second one renders
    // the loaded layout (or the fallback when the gate triggers).
    unawaited(_initLayout());
  }

  Future<void> _initLayout() async {
    final service = DashboardLayoutService.instance;
    await service.load();

    if (!mounted) return;

    // Spec `dashboard-layout` § Fallback (Scenario "Returning user sin
    // layout en Firebase"): when the persisted layout is empty AND the
    // user already finished onboarding, apply the fallback layout and
    // persist it so subsequent boots don't redo the work.
    //
    // The introSeen=='0' path leaves the layout empty by design — the
    // onboarding `_applyChoices()` will write the goals-derived layout
    // before the dashboard ever mounts.
    if (service.current.isEmpty &&
        appStateData[AppDataKey.introSeen] == '1' &&
        !service.isFutureVersion) {
      service.save(DashboardLayoutDefaults.fallback());
      await service.flush();
    }
  }

  @override
  void dispose() {
    // Persist any pending layout edits before tearing down — covers the
    // case where the user backgrounds the app mid-edit. The service is a
    // singleton so this `flush()` is safe to call at every page dispose.
    unawaited(DashboardLayoutService.instance.flush());
    unawaited(_rateSourceSubscription?.cancel());
    unawaited(_policySubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Spec `dashboard-edit-mode` § Persistencia (Scenario "App backgrounded
    // durante edición pendiente"): forzar el flush al pausar la app
    // garantiza que ediciones dentro de la ventana de 300 ms del debouncer
    // queden persistidas antes de que el SO mate el proceso.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(DashboardLayoutService.instance.flush());
    }
    // Phase 4.6 of `currency-modes-rework` — 24h scheduler tick on app
    // resume. The service self-gates against the 24h window, so this is
    // a no-op when the last successful run is recent. We deliberately
    // tie this to the dashboard lifecycle (vs main.dart) so the tick is
    // suspended while the user is in another module (calculator, edit
    // form, …) — those flows don't need fresh rates.
    if (state == AppLifecycleState.resumed) {
      unawaited(RateRefreshService.instance.maybeRunDailyTick());
    }
  }

  /// Toggle del edit mode. Al salir, fuerza un `flush()` para escribir las
  /// últimas mutaciones del debouncer antes de cambiar de pantalla.
  Future<void> _toggleEditing() async {
    if (_editing) {
      // Saliendo: persiste cualquier cambio pendiente.
      await DashboardLayoutService.instance.flush();
    }
    if (!mounted) return;
    setState(() => _editing = !_editing);
  }

  /// Spec Wave 4 task 4.3: "Restablecer según mis objetivos" — reads the
  /// onboarding goals from `appStateSettings`, materializes the
  /// `DashboardLayoutDefaults.fromGoals` layout and replaces the live
  /// service value (debounced + flushed).
  Future<void> _confirmAndResetLayoutToGoals(BuildContext context) async {
    final t = Translations.of(context).home.dashboard_widgets;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.reset_to_goals_confirm_title),
          content: Text(t.reset_to_goals_confirm_message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(Translations.of(ctx).ui_actions.cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.reset_to_goals_action),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final rawGoals = appStateSettings[SettingKey.onboardingGoals];
    Set<String> goals = const <String>{};
    if (rawGoals != null && rawGoals.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawGoals);
        if (decoded is List) {
          goals = decoded.whereType<String>().toSet();
        }
      } on FormatException {
        // Treat malformed goals as empty — `fromGoals({})` falls back to the
        // canonical layout, which is the safest behaviour for this action.
      }
    }

    final layout = DashboardLayoutDefaults.fromGoals(goals);
    DashboardLayoutService.instance.resetToFallback(layout);
    await DashboardLayoutService.instance.flush();
  }

  Future<void> _confirmAndRemove(WidgetDescriptor descriptor) async {
    final spec = DashboardWidgetRegistry.instance.get(descriptor.type);
    final name = spec?.displayName(context) ?? descriptor.type.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = Translations.of(ctx).home.dashboard_widgets;
        final ui = Translations.of(ctx).ui_actions;
        return AlertDialog(
          title: Text(t.remove_widget_title),
          content: Text(
            t.remove_widget_message.replaceAll('{name}', name),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ui.cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.remove_tooltip),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      DashboardLayoutService.instance.removeByInstanceId(descriptor.instanceId);
    }
  }

  void _openConfigEditor(WidgetDescriptor descriptor) {
    final spec = DashboardWidgetRegistry.instance.get(descriptor.type);
    final editor = spec?.configEditor;
    if (editor == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (ctx) => editor(ctx, descriptor),
    );
  }

  bool _isIncomeExpenseAtSameLevel(BuildContext context) {
    return BreakPoint.of(context).isLargerOrEqualTo(BreakpointID.sm);
  }

  /// Refresh streams downstream when the user pulls the dashboard.
  Future<void> _refreshData() async {
    setState(() {
      _refreshTick++;
    });
    await Future.delayed(const Duration(milliseconds: 300));
  }

  /// Persiste el cambio de fuente de tasas y propaga el nuevo valor a los
  /// widgets dinámicos vía el [DashboardScope]. Equivale al `setState` que
  /// tenía el viejo `_buildRateChip`.
  void _onRateSourceChanged(String source) {
    if (_rateSource == source) return;
    unawaited(
      UserSettingService.instance.setItem(
        SettingKey.preferredRateSource,
        source,
      ),
    );
    setState(() => _rateSource = source);
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
        // Single top-level subscription to the (already shared) visible
        // account ids stream — descendants receive `visibleIds` via the
        // [DashboardScope] instead of subscribing independently.
        child: StreamBuilder<List<String>>(
          stream: HiddenModeService.instance.visibleAccountIdsStream,
          builder: (context, snapshot) {
            final visibleIds = snapshot.data;
            return DashboardScope(
              dateRangeService: dateRangeService,
              rateSource: _rateSource,
              onRateSourceChanged: _onRateSourceChanged,
              refreshTick: _refreshTick,
              visibleAccountIds: visibleIds,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 80),
                child: Column(
                  children: [
                    // ── Big header (scrolls away naturally) ──
                    buildDashboadHeader(context, accountService, visibleIds),

                    // ── Edit mode banner (instrucciones cortas) ──
                    // Spec Wave 4 task 4.4: smooth fade for the banner so it
                    // doesn't pop in/out abruptly when toggling edit mode.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: _editing
                          ? KeyedSubtree(
                              key: const ValueKey<String>('edit-banner'),
                              child: _buildEditBanner(context),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey<String>('edit-banner-empty'),
                            ),
                    ),

                    // ── Body dinámico desde DashboardLayoutService ──
                    StreamBuilder<DashboardLayout>(
                      stream: DashboardLayoutService.instance.stream,
                      initialData: DashboardLayoutService.instance.current,
                      builder: (context, layoutSnapshot) {
                        final layout =
                            layoutSnapshot.data ?? DashboardLayout.empty();
                        // Spec Wave 4 task 4.4: animate the view ↔ edit
                        // body transition so widgets fade between the two
                        // renderers (300 ms is the same duration used by
                        // Material's default page transitions).
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: _editing
                              ? KeyedSubtree(
                                  key: const ValueKey<String>(
                                    'dashboard-body-edit',
                                  ),
                                  child: _DashboardEditBody(
                                    layout: layout,
                                    onDelete: _confirmAndRemove,
                                    onConfigure: _openConfigEditor,
                                  ),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey<String>(
                                    'dashboard-body-view',
                                  ),
                                  child: DashboardLayoutBody(layout: layout),
                                ),
                        );
                      },
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
            );
          },
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
    List<String>? visibleIds,
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        buildDatePeriodSelector(context),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: _editing
                              ? Translations.of(
                                  context,
                                ).home.dashboard_widgets.exit_edit_mode
                              : Translations.of(
                                  context,
                                ).home.dashboard_widgets.edit_dashboard,
                          icon: Icon(
                            _editing
                                ? Icons.check_rounded
                                : Icons.edit_outlined,
                            color: AppColors.of(context).onHeaderMuted,
                            size: 20,
                          ),
                          onPressed: () => unawaited(_toggleEditing()),
                        ),
                        // Overflow menu — solo en modo view. Spec
                        // `dashboard-edit-mode` § "Restablecer según mis
                        // objetivos" (Wave 4 task 4.3).
                        if (!_editing)
                          PopupMenuButton<String>(
                            tooltip: '',
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: AppColors.of(context).onHeaderMuted,
                              size: 20,
                            ),
                            onSelected: (value) {
                              if (value == 'reset_to_goals') {
                                unawaited(
                                  _confirmAndResetLayoutToGoals(context),
                                );
                              }
                            },
                            itemBuilder: (ctx) {
                              final t = Translations.of(
                                ctx,
                              ).home.dashboard_widgets;
                              return <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'reset_to_goals',
                                  child: Text(t.reset_to_goals_action),
                                ),
                              ];
                            },
                          ),
                      ],
                    ),
                  ],
                ),
                Divider(
                  height: 16,
                  color: AppColors.of(context).onHeaderSubtle,
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final labelStyle = Theme.of(context).textTheme.labelMedium!
                        .copyWith(color: AppColors.of(context).onHeaderMuted);

                    // `visibleIds` is pushed down from the single top-level
                    // StreamBuilder on HiddenModeService.visibleAccountIdsStream
                    // in `build()`. While Hidden Mode is locked the list
                    // excludes savings account ids, so the income/expense
                    // totals are computed without their transactions. When
                    // null (first frame before the stream emits) fall back to
                    // unfiltered totals; the parent rebuilds on emission.
                    final accountFilter = visibleIds == null
                        ? null
                        : TransactionFilterSet(accountsIDs: visibleIds);

                    final incomeAndExpenseCards = [
                      IncomeOrExpenseCard(
                        type: TransactionType.expense,
                        periodState: dateRangeService,
                        labelStyle: labelStyle,
                        filters: accountFilter,
                      ),
                      IncomeOrExpenseCard(
                        type: TransactionType.income,
                        periodState: dateRangeService,
                        labelStyle: labelStyle,
                        filters: accountFilter,
                      ),
                    ];

                    final totalBalance = TotalBalanceSummaryWidget(
                      dateRangeService: dateRangeService,
                      rateSource: _rateSource,
                      refreshTick: _refreshTick,
                      alignStart: _isIncomeExpenseAtSameLevel(context),
                      onRateSourceChanged: _onRateSourceChanged,
                    );

                    if (_isIncomeExpenseAtSameLevel(context)) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        spacing: 16,
                        children: [
                          totalBalance,
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
                        totalBalance,
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
        style: TextStyle(color: AppColors.of(context).onHeaderMuted),
      ),
      backgroundColor: AppColors.of(context).onHeader.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(color: AppColors.of(context).onHeader.withValues(alpha: 0.2)),
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
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
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
                backgroundColor: AppColors.of(context).onHeader.withValues(alpha: 0.15),
                border: Border.all(
                  width: 2,
                  color: AppColors.of(context).onHeader.withValues(alpha: 0.5),
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
                      color: AppColors.of(context).onHeaderMuted,
                    ),
                  ),
                  Text(
                    appStateSettings[SettingKey.userName] ?? 'User',
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      fontSize: 18,
                      overflow: TextOverflow.fade,
                      color: AppColors.of(context).onHeader,
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

  SkeletonizerConfigData _getSkeletonizerConfig(BuildContext context) {
    return SkeletonizerConfigData(
      effect: ShimmerEffect(
        baseColor: Colors.white.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.2),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Banner de instrucciones que aparece debajo del header solo en edit
  /// mode. Texto en español; Wave 4 lo migra a slang.
  Widget _buildEditBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.18),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.touch_app_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                Translations.of(
                  context,
                ).home.dashboard_widgets.edit_banner,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color onHeaderSmallTextColor(BuildContext context) =>
    AppColors.of(context).onHeaderMuted;

/// Renderer del body cuando `_editing == true`. Spec
/// `dashboard-edit-mode`. Forza todos los items a `fullWidth` (ADR-5),
/// envuelve cada uno en `EditableWidgetFrame` y los coloca dentro de un
/// `ReorderableListView.builder`. Al final agrega un botón "+ Agregar
/// widget" que abre el `AddWidgetSheet`.
class _DashboardEditBody extends StatelessWidget {
  const _DashboardEditBody({
    required this.layout,
    required this.onDelete,
    required this.onConfigure,
  });

  final DashboardLayout layout;
  final void Function(WidgetDescriptor descriptor) onDelete;
  final void Function(WidgetDescriptor descriptor) onConfigure;

  @override
  Widget build(BuildContext context) {
    final registry = DashboardWidgetRegistry.instance;
    // Only include descriptors whose type is registered. Unregistered types
    // (e.g. stale data from a future schema or a removed widget) must be
    // filtered out in BOTH view mode (DashboardLayoutBody) and edit mode so
    // they never appear as empty ghost frames.
    final descriptors = layout.widgets
        .where((d) => registry.get(d.type) != null)
        .toList(growable: false);

    // Pre-compute the mapping from filtered-list index → full-list index so
    // that reorder operations are applied to the correct positions in the
    // underlying layout (which may contain unregistered descriptors that are
    // invisible in the edit list but still occupy slots in the service list).
    final fullWidgets = layout.widgets;
    final indexMap = <int, int>{};
    var filteredIdx = 0;
    for (var i = 0; i < fullWidgets.length; i++) {
      if (registry.get(fullWidgets[i].type) != null) {
        indexMap[filteredIdx] = i;
        filteredIdx++;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        children: [
          // ReorderableListView necesita `shrinkWrap: true` y
          // `physics: NeverScrollable` para vivir dentro de un
          // SingleChildScrollView (el dashboard ya scrollea por su cuenta).
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) =>
                Material(type: MaterialType.transparency, child: child),
            itemCount: descriptors.length,
            onReorder: (from, to) {
              // Translate the filtered-list indices to full-list indices before
              // delegating to the service, which operates on layout.widgets
              // (unfiltered). Without this translation, unregistered widgets
              // silently shift the target positions and corrupt the order.
              final fullFrom = indexMap[from];
              if (fullFrom == null) return;

              // `to` in ReorderableListView semantics is the desired position
              // AFTER the removal of `from`. Map both boundary indices: the
              // "before-first" boundary (to == 0) stays 0; the "after-last"
              // boundary maps to fullWidgets.length. Interior positions map to
              // the full-list index of the filtered item at that slot.
              final int fullTo;
              if (to == 0) {
                fullTo = 0;
              } else if (to >= descriptors.length) {
                fullTo = fullWidgets.length;
              } else {
                fullTo = indexMap[to] ?? fullWidgets.length;
              }

              DashboardLayoutService.instance.reorder(fullFrom, fullTo);
            },
            itemBuilder: (context, index) {
              final descriptor = descriptors[index];
              final spec = registry.get(descriptor.type)!;
              // Si el widget tiene `shouldRender == false` ahora mismo, en
              // edit mode mostramos el frame con un placeholder en lugar
              // del builder real — el spec se reserva el derecho de
              // devolver `SizedBox.shrink()` cuando no tiene datos, pero
              // en edit mode el usuario necesita ver el slot para poder
              // quitarlo.
              final shouldRenderBody =
                  spec.shouldRender?.call(descriptor) ?? true;
              final built = shouldRenderBody
                  ? spec.builder(context, descriptor, editing: true)
                  : const SizedBox.shrink();
              return ReorderableDelayedDragStartListener(
                key: ValueKey<String>('edit-${descriptor.instanceId}'),
                index: index,
                child: EditableWidgetFrame(
                  descriptor: descriptor,
                  spec: spec,
                  showEmptyPlaceholder: !shouldRenderBody,
                  onDelete: () => onDelete(descriptor),
                  onConfigure: spec.configEditor != null
                      ? () => onConfigure(descriptor)
                      : null,
                  child: built,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => unawaited(showAddWidgetSheet(context)),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Agregar widget'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
