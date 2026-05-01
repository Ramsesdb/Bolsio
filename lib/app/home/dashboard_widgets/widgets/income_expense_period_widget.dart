import 'package:flutter/material.dart';
import 'package:nitido/app/home/dashboard_widgets/dashboard_scope.dart';
import 'package:nitido/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:nitido/app/home/dashboard_widgets/registry.dart';
import 'package:nitido/app/home/widgets/income_or_expense_card.dart';
import 'package:nitido/core/models/date-utils/date_period_state.dart';
import 'package:nitido/core/models/transaction/transaction_type.enum.dart';
import 'package:nitido/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

/// Modos del widget — coinciden con el contrato declarado en
/// `WidgetDescriptor.config['mode']`. Encapsulamos la (de)serialización en
/// el enum para que el render no tenga que tocar strings.
enum IncomeExpensePeriodMode {
  income,
  expense,
  both;

  static IncomeExpensePeriodMode fromConfig(Object? raw) {
    if (raw is String) {
      for (final value in IncomeExpensePeriodMode.values) {
        if (value.name == raw) return value;
      }
    }
    return IncomeExpensePeriodMode.both;
  }
}

/// Wrapper público que reúne los `IncomeOrExpenseCard` del header — ambos,
/// solo gasto, o solo ingreso — y los renderiza con el periodo, fuente de
/// tasas y filtro de cuentas activos.
///
/// Wave 1B sólo registra el spec; el dashboard sigue usando
/// [IncomeOrExpenseCard] inline en su header. Wave 2 cambia la composición
/// para delegar aquí.
class IncomeExpensePeriodWidget extends StatelessWidget {
  const IncomeExpensePeriodWidget({
    super.key,
    required this.dateRangeService,
    required this.mode,
    this.rateSource,
    this.accountIds,
    this.categoryIds,
    this.labelStyle,
  });

  final DatePeriodState dateRangeService;
  final IncomeExpensePeriodMode mode;

  /// Fuente de tasas (`'bcv'` / `'paralelo'`). `null` desactiva el
  /// equivalente Bs en cada tarjeta.
  final String? rateSource;

  /// Cuentas filtradas (resultado ya intersectado con Hidden Mode por el
  /// dashboard). `null` = sin filtro de cuentas.
  final List<String>? accountIds;

  /// Categorías filtradas. `null` = sin filtro.
  final List<String>? categoryIds;

  /// Estilo del label "Ingreso" / "Gasto" — se hereda de la tipografía del
  /// header del dashboard.
  final TextStyle? labelStyle;

  TransactionFilterSet? _buildFilterSet() {
    if ((accountIds == null || accountIds!.isEmpty) &&
        (categoryIds == null || categoryIds!.isEmpty)) {
      return null;
    }
    return TransactionFilterSet(
      accountsIDs: accountIds,
      categoriesIds: categoryIds,
    );
  }

  Widget _buildCard(TransactionType type) {
    return IncomeOrExpenseCard(
      type: type,
      periodState: dateRangeService,
      labelStyle: labelStyle,
      filters: _buildFilterSet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case IncomeExpensePeriodMode.income:
        return _buildCard(TransactionType.income);
      case IncomeExpensePeriodMode.expense:
        return _buildCard(TransactionType.expense);
      case IncomeExpensePeriodMode.both:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCard(TransactionType.expense),
            _buildCard(TransactionType.income),
          ],
        );
    }
  }
}

/// Registra el spec del widget `incomeExpensePeriod`.
void registerIncomeExpensePeriodWidget() {
  DashboardWidgetRegistry.instance.register(
    DashboardWidgetSpec(
      type: WidgetType.incomeExpensePeriod,
      displayName: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.income_expense_period.name,
      description: (ctx) => Translations.of(
        ctx,
      ).home.dashboard_widgets.income_expense_period.description,
      icon: Icons.swap_vert_rounded,
      defaultSize: WidgetSize.medium,
      allowedSizes: const <WidgetSize>{
        WidgetSize.medium,
        WidgetSize.fullWidth,
      },
      defaultConfig: const <String, dynamic>{
        'mode': 'both',
        'period': '30d',
        'currency': null,
      },
      recommendedFor: const <String>{'track_expenses', 'budget', 'analyze'},
      builder: (context, descriptor, {required editing}) {
        // Wave 2 — render real. Lee `dateRangeService` / `rateSource`
        // del [DashboardScope] y `mode` / `accountIds` / `categoryIds`
        // de `descriptor.config`.
        final scope = DashboardScope.of(context);
        final mode = IncomeExpensePeriodMode.fromConfig(
          descriptor.config['mode'],
        );
        final rawAccounts = descriptor.config['accountIds'];
        final cfgAccounts = rawAccounts is List
            ? rawAccounts.whereType<String>().toList(growable: false)
            : null;
        // Intersectar el subset declarado con la lista visible de Hidden
        // Mode. `null` significa "sin filtro adicional"; lista vacía
        // significa "el config-filter excluyó todo" — preservar el `[]`
        // para que el query Drift devuelva 0 resultados (cero ingresos /
        // gastos) sin fallar.
        final visible = scope.visibleAccountIds;
        List<String>? effectiveAccounts;
        if (cfgAccounts == null || cfgAccounts.isEmpty) {
          effectiveAccounts = visible;
        } else if (visible == null) {
          effectiveAccounts = cfgAccounts;
        } else {
          effectiveAccounts = cfgAccounts
              .where(visible.contains)
              .toList(growable: false);
        }
        final rawCategories = descriptor.config['categoryIds'];
        final cfgCategories = rawCategories is List
            ? rawCategories.whereType<String>().toList(growable: false)
            : null;
        return KeyedSubtree(
          key: ValueKey('${descriptor.type.name}-${descriptor.instanceId}'),
          child: IncomeExpensePeriodWidget(
            dateRangeService: scope.dateRangeService,
            mode: mode,
            rateSource: scope.rateSource,
            accountIds: effectiveAccounts,
            categoryIds: cfgCategories,
          ),
        );
      },
    ),
  );
}
