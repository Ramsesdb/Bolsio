import 'package:flutter/material.dart';
import 'package:wallex/app/ai/ai_hub.page.dart';
import 'package:wallex/app/chat/wallex_chat.page.dart';
import 'package:wallex/core/database/services/pending_import/pending_import_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/models/date-utils/date_period_state.dart';
import 'package:wallex/core/routes/destinations.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/ai/spending_insights_service.dart';
import 'package:wallex/core/utils/unique_app_widgets_keys.dart';

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.selectedDestination});

  final AppMenuDestinationsID selectedDestination;

  @override
  Widget build(BuildContext context) {
    final menuItems = getDestinations(context);
    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';

    int selectedNavItemIndex = menuItems.indexWhere(
      (element) => element.id == selectedDestination,
    );

    if (!(0 <= selectedNavItemIndex &&
        selectedNavItemIndex < menuItems.length)) {
      selectedNavItemIndex = menuItems.indexWhere(
        (element) => element.id == AppMenuDestinationsID.settings,
      );
      if (selectedNavItemIndex < 0) selectedNavItemIndex = 0;
    }

    final leftItems =
        menuItems.length >= 2 ? menuItems.sublist(0, 2) : menuItems;
    final rightItems =
        menuItems.length > 2 ? menuItems.sublist(2) : <MainMenuDestination>[];

    return StreamBuilder<int>(
      stream: PendingImportService.instance.watchPendingCount(),
      initialData: 0,
      builder: (context, snapshot) {
        final pendingCount = snapshot.data ?? 0;
        final cs = Theme.of(context).colorScheme;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Nav bar
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(color: cs.outlineVariant, width: 0.3),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      ...leftItems.map((e) {
                        final idx = menuItems.indexOf(e);
                        return _NavItem(
                          item: e,
                          selected: idx == selectedNavItemIndex,
                          cs: cs,
                          pendingCount:
                              e.id == AppMenuDestinationsID.transactions
                                  ? pendingCount
                                  : 0,
                          onTap: () =>
                              tabsPageKey.currentState?.changePage(e.id),
                        );
                      }),
                      const Expanded(child: SizedBox()),
                      ...rightItems.map((e) {
                        final idx = menuItems.indexOf(e);
                        return _NavItem(
                          item: e,
                          selected: idx == selectedNavItemIndex,
                          cs: cs,
                          pendingCount:
                              e.id == AppMenuDestinationsID.transactions
                                  ? pendingCount
                                  : 0,
                          onTap: () =>
                              tabsPageKey.currentState?.changePage(e.id),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),

            // Floating AI section (overflows above nav bar)
            if (aiEnabled)
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: _FloatingAiSection(cs: cs),
              ),
          ],
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.cs,
    required this.pendingCount,
    required this.onTap,
  });

  final MainMenuDestination item;
  final bool selected;
  final ColorScheme cs;
  final int pendingCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget icon = Icon(
      selected ? (item.selectedIcon ?? item.icon) : item.icon,
      size: 24,
      color: selected ? cs.primary : cs.onSurfaceVariant,
    );

    if (pendingCount > 0) {
      icon = Badge.count(count: pendingCount, child: icon);
    }

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingAiSection extends StatefulWidget {
  const _FloatingAiSection({required this.cs});
  final ColorScheme cs;

  @override
  State<_FloatingAiSection> createState() => _FloatingAiSectionState();
}

class _FloatingAiSectionState extends State<_FloatingAiSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;

  String? _insightText;
  bool _loadingInsight = true;
  bool _dismissed = false;

  bool get _hasUsefulInsight {
    if (_insightText == null || _insightText!.isEmpty) return false;
    final lower = _insightText!.toLowerCase();
    if (lower.contains('no hay cambios significativos')) return false;
    if (lower.contains('no hay suficientes datos')) return false;
    if (lower.contains('no se pudo generar')) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _scaleAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _glowAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Defer the AI insight HTTP call: the first frame should NOT wait on
    // NexusAI latency (~2s/call on MIUI cold start). Wait until after the
    // first frame paints, then add a 5s delay so the rest of the app (DB
    // streams, images, background service) has room to settle before we
    // fire the insights request. Cancelled cleanly if the widget is
    // disposed before the delay fires.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 5), () {
        if (!mounted) return;
        _fetchInsight();
      });
    });
  }

  Future<void> _fetchInsight() async {
    try {
      final result = await SpendingInsightsService.instance.generateInsights(
        periodState: const DatePeriodState(),
      );
      if (mounted) {
        setState(() {
          _insightText = result?.text;
          _loadingInsight = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInsight = false);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final showInsight = !_loadingInsight && !_dismissed && _hasUsefulInsight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showInsight)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: () => RouteUtils.pushRoute(const AiHubPage()),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 48),
                padding: const EdgeInsets.only(
                    left: 14, top: 8, bottom: 8, right: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI INSIGHT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _insightText!.length > 80
                                ? '${_insightText!.substring(0, 80)}...'
                                : _insightText!,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 14,
                        onPressed: () => setState(() => _dismissed = true),
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Glowing AI button → chat
        GestureDetector(
          onTap: () => RouteUtils.pushRoute(const WallexChatPage()),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnim.value,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [cs.primary, cs.tertiary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            cs.primary.withValues(alpha: _glowAnim.value),
                        blurRadius: 14 + 6 * _glowAnim.value,
                        spreadRadius: 1.5 * _glowAnim.value,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: cs.onPrimary,
                    size: 24,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
