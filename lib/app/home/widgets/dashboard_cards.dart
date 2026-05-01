import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nitido/app/home/dashboard_widgets/widgets/pending_imports_alert_widget.dart';
import 'package:nitido/app/stats/stats_page.dart';
import 'package:nitido/app/stats/widgets/balance_bar_chart.dart';
import 'package:nitido/app/stats/widgets/fund_evolution_info.dart';
import 'package:nitido/app/stats/widgets/movements_distribution/pie_chart_by_categories.dart';
import 'package:nitido/core/models/date-utils/date_period_state.dart';
import 'package:nitido/core/presentation/responsive/breakpoints.dart';
import 'package:nitido/core/presentation/responsive/responsive_row_column.dart';
import 'package:nitido/core/presentation/widgets/card_with_header.dart';
import 'package:nitido/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/core/presentation/app_colors.dart';
import 'package:nitido/core/services/finance_health_service.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

class DashboardCards extends StatefulWidget {
  const DashboardCards({
    super.key,
    required this.dateRangeService,
    this.visibleIds,
  });

  final DatePeriodState dateRangeService;

  /// Visible account ids passed down from the dashboard's single
  /// `HiddenModeService.visibleAccountIdsStream` subscription. When `null`
  /// (first frame before the stream emits) the finance-health filter does
  /// not constrain accounts and will re-render once the parent emits.
  final List<String>? visibleIds;

  @override
  State<DashboardCards> createState() => _DashboardCardsState();
}

class _DashboardCardsState extends State<DashboardCards> {
  /// Memoized instance so rebuilds driven by parent stream emissions don't
  /// allocate a fresh `FinanceHealthService` every frame.
  late final FinanceHealthService _healthService = FinanceHealthService();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final dateRangeService = widget.dateRangeService;
    final visibleIds = widget.visibleIds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Auto-import pending banner — extraído como widget público en
        // Wave 1B; el componente decide si renderizar o devolver
        // SizedBox.shrink() según el conteo en streaming.
        const PendingImportsAlertWidget(),


        ResponsiveRowColumn.withSymetricSpacing(
      direction: BreakPoint.of(context).isLargerThan(BreakpointID.md)
          ? Axis.horizontal
          : Axis.vertical,
      rowCrossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        ResponsiveRowColumnItem(
          rowFit: FlexFit.tight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Respect Hidden Mode: while locked, `visibleIds` excludes
              // savings account ids, so the health score is computed
              // **without** those accounts' transactions — matching the
              // stats-page semantics (see [FinanceHealthDetails] call site
              // in stats_page.dart). When Hidden Mode is disabled the list
              // contains every id and the filter is a no-op. `visibleIds`
              // is passed down from the dashboard's single upstream
              // subscription to avoid re-running the combineLatest pipeline.
              StreamBuilder(
                stream: _healthService.getHealthyValue(
                  filters: TransactionFilterSet(
                    minDate: dateRangeService.startDate,
                    maxDate: dateRangeService.endDate,
                    accountsIDs: visibleIds,
                  ),
                ),
                builder: (context, snapshot) {
                  final score = snapshot.hasData
                      ? (snapshot.data!.healthyScore ?? 0)
                      : 0.0;
                  return _HealthRingCard(
                    score: score,
                    onTap: () => RouteUtils.pushRoute(
                      StatsPage(
                        dateRangeService: dateRangeService,
                        initialIndex: 0,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              CardWithHeader(
                title: t.stats.by_categories,
                body: PieChartByCategories(datePeriodState: dateRangeService),
                footer: CardFooterWithSingleButton(
                  onButtonClick: () => RouteUtils.pushRoute(
                    StatsPage(
                      dateRangeService: dateRangeService,
                      initialIndex: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        ResponsiveRowColumnItem(
          rowFit: FlexFit.tight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CardWithHeader(
                title: t.stats.balance_evolution,
                bodyPadding: const EdgeInsets.all(16),
                body: FundEvolutionInfo(dateRange: dateRangeService),
                footer: CardFooterWithSingleButton(
                  onButtonClick: () {
                    RouteUtils.pushRoute(
                      StatsPage(
                        dateRangeService: dateRangeService,
                        initialIndex: 2,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              CardWithHeader(
                title: t.stats.by_periods,
                bodyPadding: const EdgeInsets.only(
                  bottom: 12,
                  top: 24,
                  right: 16,
                ),
                body: BalanceBarChart(
                  dateRange: dateRangeService,
                  filters: TransactionFilterSet(
                    minDate: dateRangeService.startDate,
                    maxDate: dateRangeService.endDate,
                  ),
                ),
                footer: CardFooterWithSingleButton(
                  onButtonClick: () {
                    RouteUtils.pushRoute(
                      StatsPage(
                        dateRangeService: dateRangeService,
                        initialIndex: 3,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    ),
      ],
    );
  }
}

class _HealthRingCard extends StatelessWidget {
  const _HealthRingCard({required this.score, required this.onTap});

  final double score;
  final VoidCallback onTap;

  static const _monthsEs = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  String _monthName() {
    try {
      return DateFormat.MMMM('es').format(DateTime.now());
    } catch (_) {
      return _monthsEs[DateTime.now().month - 1];
    }
  }

  String _bucketLabel(double score, String month) {
    if (score >= 80) return 'En excelente forma · $month';
    if (score >= 60) return 'Buen ritmo · $month';
    if (score >= 40) return 'En la media · $month';
    if (score >= 20) return 'Atención · $month';
    return 'Crítico · $month';
  }

  @override
  Widget build(BuildContext context) {
    final month = _monthName();
    final title = _bucketLabel(score, month);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;
    final onSurface = colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? primary.withValues(alpha: 0.08)
            : Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? primary.withValues(alpha: 0.1)
              : Colors.transparent,
          width: isDark ? 0.5 : 0,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(56, 56),
                        painter: _HealthRingPainter(
                          score: score,
                          trackColor: onSurface.withValues(alpha: 0.08),
                          dangerColor: AppColors.of(context).danger,
                          midColor: colorScheme.primary,
                          successColor: AppColors.of(context).success,
                        ),
                      ),
                      Text(
                        '${score.round()}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'SALUD FINANCIERA',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: onSurface.withValues(alpha: 0.55),
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: onSurface,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Toca para ver tu desglose mensual',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthRingPainter extends CustomPainter {
  _HealthRingPainter({
    required this.score,
    required this.trackColor,
    required this.dangerColor,
    required this.midColor,
    required this.successColor,
  });

  final double score;
  final Color trackColor;
  final Color dangerColor;
  final Color midColor;
  final Color successColor;

  Color _progressColor(double s) {
    if (s <= 50) {
      return Color.lerp(dangerColor, midColor, (s / 50).clamp(0.0, 1.0))!;
    }
    return Color.lerp(midColor, successColor, ((s - 50) / 50).clamp(0.0, 1.0))!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 4) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final progressPaint = Paint()
      ..color = _progressColor(score)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * (score / 100).clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HealthRingPainter old) =>
      old.score != score ||
      old.dangerColor != dangerColor ||
      old.midColor != midColor ||
      old.successColor != successColor;
}
