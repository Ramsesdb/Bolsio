import 'package:flutter/material.dart';
import 'package:wallex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:wallex/app/home/dashboard_widgets/registry.dart';
import 'package:wallex/core/services/dolar_api_service.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Tarjeta pública con la tabla de tasas de cambio (USD / EUR × BCV /
/// Paralelo / Promedio). Es el extracto literal de
/// `dashboard.page.dart::_buildRatesCard` y de los helpers privados que
/// construían las filas.
///
/// Wave 1B no toca la composición del dashboard — `dashboard.page.dart`
/// pasa a llamar a este widget en lugar de la función inline. Wave 2 lo
/// agregará al render dinámico.
///
/// Las opciones del spec (`currencies`, `sources`, `showEvolutionChart`)
/// existen para que [Wave 2] / [Wave 3] puedan filtrarlas — Wave 1B
/// preserva la UI: USD + EUR, BCV + Paralelo, sin evolución gráfica.
class ExchangeRateCardWidget extends StatelessWidget {
  const ExchangeRateCardWidget({
    super.key,
    this.currencies = const <String>['USD', 'EUR'],
    this.sources = const <String>['bcv', 'paralelo'],
    this.showEvolutionChart = false,
  });

  /// Subset de divisas a mostrar. Wave 1B ignora la opción y muestra ambas
  /// — preservar UI es prioridad. La validación se hará en Wave 2.5
  /// (configEditor).
  final List<String> currencies;

  /// Subset de fuentes a mostrar. Wave 1B preserva BCV + Paralelo.
  final List<String> sources;

  /// Reservado para Wave 3 — gráfica de evolución de la tasa.
  final bool showEvolutionChart;

  @override
  Widget build(BuildContext context) {
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
          FutureBuilder<Map<String, double?>>(
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

    // Use cached values if fresh, otherwise fetch.
    if (api.isStale) {
      await api.fetchAll();
    }

    // EUR rates may fail due to API rate-limiting after multiple calls.
    // Retry EUR specifically if missing.
    if (api.eurOficialRate == null || api.eurParaleloRate == null) {
      await api.fetchAllEurRates();
    }

    return <String, double?>{
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
}

/// Registra el spec del widget `exchangeRateCard`.
void registerExchangeRateCardWidget() {
  DashboardWidgetRegistry.instance.register(
    DashboardWidgetSpec(
      type: WidgetType.exchangeRateCard,
      displayName: (ctx) =>
          Translations.of(ctx).home.dashboard_widgets.exchange_rate_card.name,
      description: (ctx) => Translations.of(
        ctx,
      ).home.dashboard_widgets.exchange_rate_card.description,
      icon: Icons.currency_exchange,
      defaultSize: WidgetSize.medium,
      allowedSizes: const <WidgetSize>{
        WidgetSize.medium,
        WidgetSize.fullWidth,
      },
      defaultConfig: const <String, dynamic>{
        'pair': 'USD_VES',
        'source': null,
        'currencies': <String>['USD', 'EUR'],
        'sources': <String>['bcv', 'paralelo'],
        'showEvolutionChart': false,
      },
      recommendedFor: const <String>{'save_usd', 'analyze'},
      builder: (context, descriptor, {required editing}) {
        // Wave 2 — render real. Lee `currencies` / `sources` /
        // `showEvolutionChart` del descriptor.config. Wave 1 ya construyó
        // la UI canónica con USD+EUR / BCV+Paralelo; los parámetros
        // siguen ahí para que Wave 2.5 (configEditor) los pueda mutar.
        final rawCurrencies = descriptor.config['currencies'];
        final currencies = rawCurrencies is List
            ? rawCurrencies.whereType<String>().toList(growable: false)
            : const <String>['USD', 'EUR'];
        final rawSources = descriptor.config['sources'];
        final sources = rawSources is List
            ? rawSources.whereType<String>().toList(growable: false)
            : const <String>['bcv', 'paralelo'];
        final rawShowChart = descriptor.config['showEvolutionChart'];
        final showChart = rawShowChart is bool ? rawShowChart : false;
        return KeyedSubtree(
          key: ValueKey('${descriptor.type.name}-${descriptor.instanceId}'),
          child: ExchangeRateCardWidget(
            currencies: currencies.isEmpty
                ? const <String>['USD', 'EUR']
                : currencies,
            sources: sources.isEmpty
                ? const <String>['bcv', 'paralelo']
                : sources,
            showEvolutionChart: showChart,
          ),
        );
      },
    ),
  );
}
