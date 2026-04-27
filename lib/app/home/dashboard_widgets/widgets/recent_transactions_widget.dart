import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/dashboard_scope.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';
import 'package:wallex/app/transactions/transactions.page.dart';
import 'package:wallex/app/transactions/widgets/transaction_list.dart';
import 'package:wallex/app/transactions/widgets/transaction_list_tile.dart';
import 'package:wallex/core/database/services/transaction/transaction_service.dart';
import 'package:wallex/core/models/transaction/transaction_status.enum.dart';
import 'package:wallex/core/presentation/widgets/card_with_header.dart';
import 'package:wallex/core/presentation/widgets/transaction_filter/transaction_filter_set.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Wrapper público que muestra las últimas N transacciones del usuario,
/// con tap a la fila navegando al detalle (vía la propia [TransactionListTile])
/// y un footer "Ver todas" que abre [TransactionsPage] cuando hay más
/// movimientos que el límite del widget.
///
/// El widget reusa el componente base [TransactionListComponent] — Wave 1B
/// no introduce un componente nuevo, sólo lo encapsula como una entrada del
/// dashboard dinámico.
class RecentTransactionsWidget extends StatelessWidget {
  const RecentTransactionsWidget({
    super.key,
    this.limit = defaultLimit,
    this.accountIds,
    this.categoryIds,
  });

  /// Default declarado en el spec (`recentTransactions.defaultConfig.limit = 5`).
  static const int defaultLimit = 5;

  /// Cap superior según el spec (`limit fuera de rango` → 20).
  static const int maxLimit = 20;

  /// Cap inferior — un widget con `limit <= 0` no aporta nada y rompería el
  /// `LIMIT N` de Drift. El componente se reduce a su empty state.
  static const int minLimit = 1;

  /// Límite solicitado vía `WidgetDescriptor.config['limit']`.
  /// Se capa al rango `[minLimit, maxLimit]` antes de usarse.
  final int limit;

  /// Filtro de cuentas declarado en config. `null` = todas las cuentas.
  final List<String>? accountIds;

  /// Filtro de categorías declarado en config. `null` = todas.
  final List<String>? categoryIds;

  /// Aplica los caps del spec. Pública por test-friendliness y para el
  /// configEditor (Wave 2.5) que valida la entrada del usuario.
  static int clampLimit(int value) {
    if (value < minLimit) return minLimit;
    if (value > maxLimit) return maxLimit;
    return value;
  }

  TransactionFilterSet _filters() {
    return TransactionFilterSet(
      // Excluimos transacciones pendientes / void para que el widget se
      // alinee con el comportamiento de "últimas transacciones" de la
      // ficha de cuenta — el usuario no espera ver pending notifications
      // en el dashboard principal.
      status: TransactionStatus.notIn({
        TransactionStatus.pending,
        TransactionStatus.voided,
      }),
      accountsIDs: accountIds,
      categoriesIds: categoryIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final effectiveLimit = clampLimit(limit);
    final filters = _filters();

    return CardWithHeader(
      title: t.home.last_transactions,
      bodyPadding: const EdgeInsets.symmetric(vertical: 6),
      footer: StreamBuilder<int>(
        stream: TransactionService.instance.countTransactions(filters: filters),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data! <= effectiveLimit) {
            return const SizedBox.shrink();
          }
          return CardFooterWithSingleButton(
            onButtonClick: () => RouteUtils.pushRoute(
              TransactionsPage(filters: filters),
            ),
          );
        },
      ),
      body: TransactionListComponent(
        filters: filters,
        limit: effectiveLimit,
        showGroupDivider: false,
        tileBuilder: (transaction) => TransactionListTile(
          transaction: transaction,
          heroTag: 'dashboard__recent-tr-icon-${transaction.id}',
        ),
        onEmptyList: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            t.transaction.list.empty,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Registra el spec del widget `recentTransactions`.
void registerRecentTransactionsWidget() {
  DashboardWidgetRegistry.instance.register(
    DashboardWidgetSpec(
      type: WidgetType.recentTransactions,
      displayName: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.recent_transactions.name,
      description: (ctx) => Translations.of(
        ctx,
      ).home.dashboard_widgets.recent_transactions.description,
      icon: Icons.receipt_long_rounded,
      defaultSize: WidgetSize.fullWidth,
      allowedSizes: const <WidgetSize>{WidgetSize.fullWidth},
      defaultConfig: const <String, dynamic>{
        'limit': RecentTransactionsWidget.defaultLimit,
        'accountIds': null,
        'categoryIds': null,
        'showCategories': true,
      },
      recommendedFor: const <String>{
        'track_expenses',
        'reduce_debt',
        'budget',
        'analyze',
      },
      builder: (context, descriptor, {required editing}) {
        // Wave 2 — render real. Lee el `limit` y filtros de
        // `descriptor.config` (clampeados al rango [1, 20]). Las cuentas
        // visibles tras Hidden Mode se intersectan con el subset de config
        // — coherente con el resto de widgets del dashboard.
        final rawLimit = descriptor.config['limit'];
        final limit = rawLimit is int
            ? rawLimit
            : (rawLimit is num ? rawLimit.toInt() : RecentTransactionsWidget.defaultLimit);
        final rawAccounts = descriptor.config['accountIds'];
        final cfgAccounts = rawAccounts is List
            ? rawAccounts.whereType<String>().toList(growable: false)
            : null;
        final scope = DashboardScope.maybeOf(context);
        final visible = scope?.visibleAccountIds;
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
          child: RecentTransactionsWidget(
            limit: limit,
            accountIds: effectiveAccounts,
            categoryIds: cfgCategories,
          ),
        );
      },
    ),
  );
}
