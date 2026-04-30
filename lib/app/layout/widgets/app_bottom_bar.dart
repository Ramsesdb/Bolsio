import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kilatex/app/ai/ai_hub.page.dart';
import 'package:kilatex/app/chat/wallex_chat.page.dart';
import 'package:kilatex/core/database/services/pending_import/pending_import_service.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/models/date-utils/date_period_state.dart';
import 'package:kilatex/core/routes/destinations.dart';
import 'package:kilatex/core/routes/route_utils.dart';
import 'package:kilatex/core/services/ai/spending_insights_service.dart';
import 'package:kilatex/core/utils/unique_app_widgets_keys.dart';

class AppBottomBar extends StatefulWidget {
  const AppBottomBar({super.key, required this.selectedDestination});

  final AppMenuDestinationsID selectedDestination;

  static const double _barHeight = 68;
  static const double _topRadius = 28;

  @override
  State<AppBottomBar> createState() => _AppBottomBarState();
}

class _AppBottomBarState extends State<AppBottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blobController;
  int _previousIndex = 0;
  int _currentIndex = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _blobController.dispose();
    super.dispose();
  }

  void _maybeAnimateTo(int newIndex) {
    if (!_initialized) {
      _previousIndex = newIndex;
      _currentIndex = newIndex;
      _initialized = true;
      _blobController.value = 1.0;
      return;
    }
    if (newIndex == _currentIndex) return;
    _previousIndex = _currentIndex;
    _currentIndex = newIndex;
    _blobController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = getDestinations(context);
    final aiEnabled = appStateSettings[SettingKey.nexusAiEnabled] == '1';

    int selectedNavItemIndex = menuItems.indexWhere(
      (element) => element.id == widget.selectedDestination,
    );

    if (!(0 <= selectedNavItemIndex &&
        selectedNavItemIndex < menuItems.length)) {
      selectedNavItemIndex = menuItems.indexWhere(
        (element) => element.id == AppMenuDestinationsID.settings,
      );
      if (selectedNavItemIndex < 0) selectedNavItemIndex = 0;
    }

    // Schedule animation update after build (so we don't setState during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeAnimateTo(selectedNavItemIndex);
    });

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
        final vpBottom =
            MediaQuery.of(context).viewPadding.bottom;
        // 28px is the visual offset that looks correct on gesture-nav
        // phones (where the system bar is transparent and ≤28px tall).
        // On 3-button nav (vpBottom ≈ 48px) the opaque system bar is
        // taller than 28, so we use vpBottom to keep the button above it.
        final aiBottomOffset = vpBottom > 28 ? vpBottom : 28.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Glass nav bar
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppBottomBar._topRadius),
                topRight: Radius.circular(AppBottomBar._topRadius),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh.withValues(alpha: 0.65),
                    border: Border(
                      top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: AppBottomBar._barHeight,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          // 5 slots total (4 lateral + 1 center AI gap).
                          // Slot center X = (i + 0.5) * (width / 5).
                          // Indices in menuItems → slot:
                          //   left items take slots 0,1; right items 3,4.
                          final isCenterSelected = selectedNavItemIndex >= 0 &&
                              selectedNavItemIndex < menuItems.length &&
                              _slotForMenuIndex(selectedNavItemIndex,
                                      menuItems.length) ==
                                  2;

                          return Stack(
                            children: [
                              // Liquid blob behind everything.
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _BlobPainter(
                                      animation: _blobController,
                                      previousSlot: _slotForMenuIndex(
                                          _previousIndex, menuItems.length),
                                      currentSlot: _slotForMenuIndex(
                                          _currentIndex, menuItems.length),
                                      slotWidth: width / 5,
                                      barHeight: AppBottomBar._barHeight,
                                      color: cs.primary
                                          .withValues(alpha: 0.20),
                                      hidden: isCenterSelected,
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  ...leftItems.map((e) {
                                    final idx = menuItems.indexOf(e);
                                    return _NavItem(
                                      item: e,
                                      selected: idx == selectedNavItemIndex,
                                      cs: cs,
                                      pendingCount: e.id ==
                                              AppMenuDestinationsID
                                                  .transactions
                                          ? pendingCount
                                          : 0,
                                      onTap: () => tabsPageKey.currentState
                                          ?.changePage(e.id),
                                    );
                                  }),
                                  const Expanded(child: SizedBox()),
                                  ...rightItems.map((e) {
                                    final idx = menuItems.indexOf(e);
                                    return _NavItem(
                                      item: e,
                                      selected: idx == selectedNavItemIndex,
                                      cs: cs,
                                      pendingCount: e.id ==
                                              AppMenuDestinationsID
                                                  .transactions
                                          ? pendingCount
                                          : 0,
                                      onTap: () => tabsPageKey.currentState
                                          ?.changePage(e.id),
                                    );
                                  }),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Floating AI section (overflows above nav bar)
            if (aiEnabled)
              Positioned(
                left: 0,
                right: 0,
                bottom: aiBottomOffset,
                child: _FloatingAiSection(cs: cs),
              ),
          ],
        );
      },
    );
  }

  /// Maps a menuItems index (0..N-1) to its visual slot (0..4) given that
  /// slot 2 is reserved for the central AI gap.
  ///
  /// Layout: leftItems = first 2 → slots 0, 1. rightItems = rest → slots 3, 4.
  int _slotForMenuIndex(int menuIdx, int total) {
    if (total <= 2) return menuIdx.clamp(0, 1);
    if (menuIdx < 2) return menuIdx; // 0 or 1
    // Right side: menuIdx 2 → slot 3, menuIdx 3 → slot 4.
    return menuIdx + 1;
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({
    required this.animation,
    required this.previousSlot,
    required this.currentSlot,
    required this.slotWidth,
    required this.barHeight,
    required this.color,
    required this.hidden,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final int previousSlot;
  final int currentSlot;
  final double slotWidth;
  final double barHeight;
  final Color color;
  final bool hidden;

  static const double _blobHeight = 56;
  static const double _blobRadius = 22;

  @override
  void paint(Canvas canvas, Size size) {
    if (hidden) return;
    if (currentSlot == 2) return; // never draw under AI gap

    // EaseOutQuart on the raw controller value: snappier landing than cubic.
    final raw = animation.value.clamp(0.0, 1.0);
    final t = _easeOutQuart(raw);

    final prevX = (previousSlot + 0.5) * slotWidth;
    final currX = (currentSlot + 0.5) * slotWidth;
    final centerY = size.height / 2;

    // Adaptive blob width based on slot width. Conservative clamp so the
    // bulged width never invades neighbour slots.
    final blobWidth = (slotWidth * 0.94).clamp(72.0, 104.0);

    final isInTransit = animation.value > 0.0 &&
        animation.value < 1.0 &&
        previousSlot != currentSlot;

    if (!isInTransit) {
      // Rest: rrect quieto centrado en el slot del seleccionado.
      _drawBlob(
        canvas,
        centerX: currX,
        centerY: centerY,
        baseWidth: blobWidth,
        widthScale: 1.0,
      );
      return;
    }

    // In transit: linear X interpolation, subtle bulge on width only.
    // bulge = (1 - (2t - 1)^2) * 0.10 + 1.0  →  1.0 at t=0/1, max 1.10 at t=0.5.
    final bulge = (1 - (2 * t - 1) * (2 * t - 1)) * 0.10 + 1.0;
    final headX = prevX + (currX - prevX) * t;
    _drawBlob(
      canvas,
      centerX: headX,
      centerY: centerY,
      baseWidth: blobWidth,
      widthScale: bulge,
    );
  }

  void _drawBlob(
    Canvas canvas, {
    required double centerX,
    required double centerY,
    required double baseWidth,
    required double widthScale,
  }) {
    final w = baseWidth * widthScale;
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: w,
      height: _blobHeight,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_blobRadius),
    );
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, paint);
  }

  double _easeOutQuart(double x) {
    final inv = 1 - x;
    return 1 - inv * inv * inv * inv;
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) {
    return oldDelegate.previousSlot != previousSlot ||
        oldDelegate.currentSlot != currentSlot ||
        oldDelegate.slotWidth != slotWidth ||
        oldDelegate.barHeight != barHeight ||
        oldDelegate.color != color ||
        oldDelegate.hidden != hidden;
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
    final iconColor =
        selected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.85);
    final labelColor =
        selected ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.7);

    Widget icon = Icon(
      selected ? (item.selectedIcon ?? item.icon) : item.icon,
      size: 24,
      color: iconColor,
    );

    if (pendingCount > 0) {
      icon = Badge.count(count: pendingCount, child: icon);
    }

    return Expanded(
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 4),
              Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                  color: labelColor,
                ),
              ),
            ],
          ),
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
