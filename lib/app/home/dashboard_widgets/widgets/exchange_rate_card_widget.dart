import 'package:flutter/material.dart';
import 'package:kilatex/app/currencies/widgets/manual_override_dialog.dart';
import 'package:kilatex/app/currencies/widgets/rate_source_badge.dart';
import 'package:kilatex/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:kilatex/app/home/dashboard_widgets/registry.dart';
import 'package:kilatex/core/database/services/currency/currency_service.dart';
import 'package:kilatex/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/models/currency/currency_display_policy.dart';
import 'package:kilatex/core/models/currency/currency_display_policy_resolver.dart';
import 'package:kilatex/core/presentation/helpers/snackbar.dart';
import 'package:kilatex/core/services/rate_providers/rate_refresh_service.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';

/// Phase 6.4 of `currency-modes-rework`: per-pair "Tasas de cambio" card.
///
/// Each row exposes:
///   - A [RateSourceBadge] surfacing the on-disk `source` (`Auto` / `BCV` /
///     `Paralelo` / `Manual`).
///   - Tap-to-edit → opens [ManualOverrideDialog] preloaded with the row's
///     currency.
///   - A per-card refresh button that runs
///     [RateRefreshService.refreshNow] (bypasses the 12h gate).
///   - The `lastFetchedAt` timestamp ("hace 2h", "ayer", …) read from the
///     row's `date` column.
///
/// The pair set is derived from [CurrencyDisplayPolicy]:
///   - `SingleMode(USD)` → no foreign pairs to render.
///   - `SingleMode(VES)` → just USD↔VES.
///   - `SingleMode(other)` → that currency vs USD.
///   - `DualMode(USD,VES)` (unordered) → USD + EUR (BCV/Paralelo).
///   - `DualMode(other,other)` → primary↔secondary plus both vs USD.
///
/// For the 3-beta scope we keep the rendering simple and reuse the existing
/// `getExchangeRates()` stream (which returns rate rows with their
/// `source` and `date` already attached). The `currencies` config option
/// lets the dashboard registry filter which currencies appear.
class ExchangeRateCardWidget extends StatelessWidget {
  const ExchangeRateCardWidget({
    super.key,
    this.currencies = const <String>['USD', 'EUR'],
    this.sources = const <String>['bcv', 'paralelo'],
    this.showEvolutionChart = false,
  });

  /// Subset de divisas a mostrar.
  final List<String> currencies;

  /// Subset de fuentes a mostrar.
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
              Expanded(
                child: Text(
                  'Tasas de cambio',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refrescar tasas',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: () => _refreshNow(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          StreamBuilder<CurrencyDisplayPolicy>(
            stream: CurrencyDisplayPolicyResolver.instance.watch(),
            builder: (context, policySnap) {
              return _RatesList(
                currencies: currencies,
                policy: policySnap.data,
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

  Future<void> _refreshNow(BuildContext context) async {
    WallexSnackbar.success(
      SnackbarParams('Actualizando tasas...'),
    );
    try {
      final result = await RateRefreshService.instance.refreshNow();
      if (!context.mounted) return;
      if (result.totalFailure == 0 && result.totalSuccess > 0) {
        WallexSnackbar.success(
          SnackbarParams(
            'Tasas actualizadas (${result.totalSuccess})',
          ),
        );
      } else if (result.totalSuccess == 0) {
        WallexSnackbar.error(SnackbarParams('No se pudieron actualizar tasas'));
      } else {
        WallexSnackbar.success(
          SnackbarParams(
            'Tasas actualizadas parcialmente: ok=${result.totalSuccess} '
            'fallos=${result.totalFailure}',
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      WallexSnackbar.error(SnackbarParams('Error al refrescar: $e'));
    }
  }
}

/// Internal list builder. Reads the latest rate per currency via
/// [ExchangeRateService.getExchangeRates] and renders a per-row tile with
/// badge + last-update + tap-to-edit. The pair set is derived from the
/// supplied [policy] (when null we default to the `currencies` list).
class _RatesList extends StatelessWidget {
  const _RatesList({required this.currencies, required this.policy});

  final List<String> currencies;
  final CurrencyDisplayPolicy? policy;

  /// Currencies that should appear in the card. Combines the configured
  /// list with the policy-derived pair set so the card stays useful even
  /// when the user is on a non-VES dual mode.
  Set<String> _effectiveCurrencies() {
    final set = <String>{...currencies.map((c) => c.toUpperCase())};
    final p = policy;
    if (p is SingleMode) {
      // For single-mode users, focus on the currency they care about.
      if (p.code != 'USD') set.add(p.code);
    } else if (p is DualMode) {
      // For the canonical dual(USD,VES) we keep the configured set
      // (typically USD + EUR). For non-VES dual we want the primary and
      // secondary to be visible.
      if (!p.showsRateSourceChip) {
        set.add(p.primary);
        set.add(p.secondary);
      }
    }
    final pref = appStateSettings[SettingKey.preferredCurrency];
    if (pref != null) {
      // The preferred currency itself never has a row (it's the storage
      // base), so exclude it.
      set.remove(pref);
    }
    return set;
  }

  @override
  Widget build(BuildContext context) {
    final wanted = _effectiveCurrencies();
    return StreamBuilder(
      stream: ExchangeRateService.instance.getExchangeRates(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final rows = snapshot.data!
            .where((r) => wanted.contains(r.currencyCode.toUpperCase()))
            .toList();
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No hay tasas configuradas. Toca el icono de actualizar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return Column(
          children: [
            for (final row in rows)
              _RateRow(
                currencyCode: row.currencyCode,
                rate: row.exchangeRate,
                source: row.source,
                date: row.date,
              ),
          ],
        );
      },
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.currencyCode,
    required this.rate,
    required this.source,
    required this.date,
  });

  final String currencyCode;
  final double rate;
  final String? source;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _edit(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Text(
              currencyCode,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            RateSourceBadge(rawSource: source),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _humanizeAge(date),
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
            Text(
              rate.toStringAsFixed(rate >= 1000 ? 0 : 2),
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    // Resolve the Currency object so the dialog can preselect it and
    // start the user in edit mode rather than blank.
    final currency = await CurrencyService.instance
        .getCurrencyByCode(currencyCode)
        .first;
    if (!context.mounted) return;
    await showManualOverrideDialog(context, initialCurrency: currency);
  }

  String _humanizeAge(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inMinutes < 1) return 'recién';
    if (diff.inHours < 1) return 'hace ${diff.inMinutes}m';
    if (diff.inDays < 1) return 'hace ${diff.inHours}h';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
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
