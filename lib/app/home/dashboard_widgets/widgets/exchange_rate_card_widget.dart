import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:bolsio/app/currencies/widgets/manual_override_dialog.dart';
import 'package:bolsio/app/currencies/widgets/rate_source_badge.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/registry.dart';
import 'package:bolsio/core/database/services/currency/currency_service.dart';
import 'package:bolsio/core/database/services/exchange-rate/exchange_rate_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/models/exchange-rate/exchange_rate.dart';
import 'package:bolsio/core/models/currency/currency_display_policy.dart';
import 'package:bolsio/core/models/currency/currency_display_policy_resolver.dart';
import 'package:bolsio/core/presentation/helpers/snackbar.dart';
import 'package:bolsio/core/services/rate_providers/rate_refresh_service.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

/// Builder mutable usado por el spec del `exchangeRateCard` para abrir su
/// configEditor sin obligar al archivo del widget a importar el sheet
/// (que vive en `edit/exchange_rate_config_sheet.dart`). El bootstrap conecta
/// el builder real tras registrar el spec — ver
/// `registry_bootstrap.dart::registerDashboardWidgets`.
///
/// Mientras esté en `null`, el spec devuelve un placeholder informativo
/// para que el patrón sea seguro de invocar incluso si el wiring no se
/// completó (raro — solo afectaría tests que olviden bootstrap).
///
/// Misma indirección que [quickUseConfigEditorBuilder] — ver ADR-5 en
/// `openspec/changes/exchange-rate-widget-config/design.md`.
Widget Function(BuildContext, WidgetDescriptor)? exchangeRateConfigEditorBuilder;

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
    this.pivotCurrency,
  });

  /// Subset de divisas a mostrar.
  final List<String> currencies;

  /// Subset de fuentes a mostrar.
  final List<String> sources;

  /// Reservado para Wave 3 — gráfica de evolución de la tasa.
  final bool showEvolutionChart;

  /// Divisa hacia la que se convierten los valores mostrados ("1 unidad de
  /// la divisa de la fila = N unidades de pivot"). `null` ⇒ auto-derivar:
  ///   - si la policy/efectiva incluye VES → pivot = VES (caso típico VE);
  ///   - de lo contrario → pivot = `preferredCurrency`.
  /// El pivot también se excluye del set de filas para evitar self-rows.
  final String? pivotCurrency;

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
                pivotCurrency: pivotCurrency,
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
    BolsioSnackbar.success(
      SnackbarParams('Actualizando tasas...'),
    );
    try {
      final result = await RateRefreshService.instance.refreshNow();
      if (!context.mounted) return;
      if (result.totalFailure == 0 && result.totalSuccess > 0) {
        BolsioSnackbar.success(
          SnackbarParams(
            'Tasas actualizadas (${result.totalSuccess})',
          ),
        );
      } else if (result.totalSuccess == 0) {
        BolsioSnackbar.error(SnackbarParams('No se pudieron actualizar tasas'));
      } else {
        BolsioSnackbar.success(
          SnackbarParams(
            'Tasas actualizadas parcialmente: ok=${result.totalSuccess} '
            'fallos=${result.totalFailure}',
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      BolsioSnackbar.error(SnackbarParams('Error al refrescar: $e'));
    }
  }
}

/// Internal table builder. Reads the latest rate per currency via
/// [ExchangeRateService.getExchangeRates] and renders a table with:
///   - Column headers: (empty) | BCV badge | Paralelo badge | Prom. badge
///   - One row per currency showing the rate under each applicable column.
///
/// Graceful degradation: currencies with only one source (e.g. Auto from
/// Frankfurter) display their rate in the BCV column so the value is always
/// visible. The Promedio column is only shown when at least one currency has
/// both BCV and Paralelo rows. See [_RatesTable] for column layout details.
///
/// The pair set is derived from the supplied [policy] (when null we default
/// to the `currencies` list).
class _RatesList extends StatelessWidget {
  const _RatesList({
    required this.currencies,
    required this.policy,
    required this.pivotCurrency,
  });

  final List<String> currencies;
  final CurrencyDisplayPolicy? policy;

  /// Pivot explícito (config del usuario). `null` ⇒ derivar.
  final String? pivotCurrency;

  /// Pre-pivot currency set: la unión configurada + policy-derived antes de
  /// excluir el pivot. Se usa también como universo válido para auto-derivar
  /// el pivot ("VES si está, si no preferred").
  Set<String> _baseCurrencies() {
    final set = <String>{...currencies.map((c) => c.toUpperCase())};
    final p = policy;
    if (p is SingleMode) {
      if (p.code != 'USD') set.add(p.code);
    } else if (p is DualMode) {
      if (!p.showsRateSourceChip) {
        set.add(p.primary);
        set.add(p.secondary);
      }
    }
    return set;
  }

  /// Resuelve el código del pivot (la divisa hacia la que se convierten los
  /// valores). Heurística cuando no hay override del usuario:
  ///   1. si la unión incluye VES → 'VES' (caso típico VE);
  ///   2. de lo contrario → preferredCurrency del usuario;
  ///   3. fallback duro → 'USD'.
  String _resolvePivot(Set<String> baseSet) {
    final explicit = pivotCurrency?.toUpperCase().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (baseSet.contains('VES')) return 'VES';
    final pref = appStateSettings[SettingKey.preferredCurrency];
    if (pref != null && pref.isNotEmpty) return pref.toUpperCase();
    return 'USD';
  }

  /// Currencies que aparecen como filas. La pivot SIEMPRE se excluye —
  /// no tiene sentido mostrar "1 VES = 1 VES". Reintroduce la exclusión
  /// que existía antes del rework, pero ahora apuntando al pivot, no al
  /// preferredCurrency (que pueden diferir cuando el usuario fuerza un
  /// pivot manual).
  Set<String> _rowCurrencies(Set<String> baseSet, String pivot) {
    return {...baseSet}..remove(pivot);
  }

  @override
  Widget build(BuildContext context) {
    final baseSet = _baseCurrencies();
    final pivotCode = _resolvePivot(baseSet);
    final wanted = _rowCurrencies(baseSet, pivotCode);

    return StreamBuilder(
      stream: ExchangeRateService.instance.getExchangeRates(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final allRows = snapshot.data!
            .where((r) => wanted.contains(r.currencyCode.toUpperCase()))
            .toList();
        if (allRows.isEmpty || wanted.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No hay tasas configuradas. Toca el icono de actualizar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }

        // Agrupar las filas por currencyCode (preserva el orden de wanted)
        // — sólo se usa para resolver el `tapTarget` del row label y para
        // saber qué fuentes (bcv/paralelo) están disponibles para cada
        // divisa. Los VALORES mostrados se calculan vía
        // [ExchangeRateService.calculateExchangeRate] (ver _RatesTable),
        // que invierte correctamente para producir "1 row = N pivot".
        final orderedCodes = wanted.toList();
        final grouped = <String, List<ExchangeRate>>{};
        for (final r in allRows) {
          final code = r.currencyCode.toUpperCase();
          grouped.putIfAbsent(code, () => []).add(r);
        }

        final anyHasBoth = orderedCodes.any((code) {
          final group = grouped[code] ?? [];
          return group.any((r) => r.source == 'bcv') &&
              group.any((r) => r.source == 'paralelo');
        });

        return _RatesTable(
          orderedCodes: orderedCodes,
          grouped: grouped,
          showPromedioColumn: anyHasBoth,
          pivotCode: pivotCode,
        );
      },
    );
  }
}

/// Pill badge for the "Prom." column header and value cells.
/// Reuses the same visual token (`colorScheme.tertiary`) as the old
/// `_PromedioRow` badge — no hardcoded hex, consistent with Wallex theme.
class _PromedioBadge extends StatelessWidget {
  const _PromedioBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.tertiary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Prom.',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.tertiary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Table layout for exchange rates. Column structure:
///   0: currency label (flag prefix + code) — FlexColumnWidth (fills remaining)
///   1: BCV rate value — FixedColumnWidth(72)
///   2: Paralelo rate value — FixedColumnWidth(72)
///   3: Promedio value — FixedColumnWidth(72), only when [showPromedioColumn]
///
/// All value columns are right-aligned with tabular figures so digits
/// stack cleanly regardless of magnitude. Header row carries the source
/// badges as column labels.
///
/// Graceful degradation for single-source currencies: if a currency only
/// has an Auto (Frankfurter) or Manual row and no Paralelo, its rate
/// appears in column 1 (BCV slot) and columns 2–3 show `—` in dim color.
/// This avoids blank rows while keeping the table structure intact.
class _RatesTable extends StatelessWidget {
  const _RatesTable({
    required this.orderedCodes,
    required this.grouped,
    required this.showPromedioColumn,
    required this.pivotCode,
  });

  final List<String> orderedCodes;
  final Map<String, List<ExchangeRate>> grouped;
  final bool showPromedioColumn;

  /// Divisa hacia la que se convierten todos los valores de la tabla.
  /// "Fila currency = N pivot" (e.g. pivot=VES: "1 USD = 485 VES").
  final String pivotCode;

  static const double _colWidth = 72;
  static const List<String> _sources = <String>['bcv', 'paralelo'];

  String _flagFor(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
        return '\$ ';
      case 'EUR':
        return '€ ';
      case 'VES':
        return 'Bs. ';
      case 'GBP':
        return '£ ';
      case 'COP':
        return 'COP ';
      case 'BRL':
        return 'R\$ ';
      default:
        return '';
    }
  }

  /// Formato adaptativo:
  ///   - `null` → guion largo
  ///   - ≥ 1000 → sin decimales (485, 567, …)
  ///   - ≥ 0.01 → 2 decimales (1.17, 39.50, …)
  ///   - resto (sub-centésimas) → 4 decimales para que valores como
  ///     0.0021 (1 VES = 0.0021 USD) no colapsen a "0.00".
  String _fmt(double? rate) {
    if (rate == null) return '—';
    if (rate >= 1000) return rate.toStringAsFixed(0);
    if (rate.abs() >= 0.01) return rate.toStringAsFixed(2);
    return rate.toStringAsFixed(4);
  }

  /// Build the outer combineLatest stream that materializes a map of
  /// `(rowCode, source) → convertedRate?`. Single subscription per cell
  /// is replaced by N×|sources| upstream subscriptions multiplexed at the
  /// Drift watch layer (no extra DB cost — see ExchangeRateConfigSheet ADR).
  Stream<Map<(String, String), double?>> _buildRatesStream() {
    final streams = <Stream<MapEntry<(String, String), double?>>>[];
    for (final code in orderedCodes) {
      for (final src in _sources) {
        streams.add(
          ExchangeRateService.instance
              .calculateExchangeRate(
                fromCurrency: code,
                toCurrency: pivotCode,
                source: src,
              )
              .map((v) => MapEntry((code, src), v)),
        );
      }
    }
    if (streams.isEmpty) {
      return Stream<Map<(String, String), double?>>.value(
        const <(String, String), double?>{},
      );
    }
    return Rx.combineLatestList(streams).map((entries) {
      final map = <(String, String), double?>{};
      for (final e in entries) {
        map[e.key] = e.value;
      }
      return map;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<(String, String), double?>>(
      stream: _buildRatesStream(),
      builder: (context, snapshot) {
        final converted = snapshot.data ?? const <(String, String), double?>{};
        return _buildTable(context, converted);
      },
    );
  }

  Widget _buildTable(
    BuildContext context,
    Map<(String, String), double?> converted,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dimColor = cs.onSurface.withValues(alpha: 0.38);

    final columnWidths = <int, TableColumnWidth>{
      0: const FlexColumnWidth(),
      1: const FixedColumnWidth(_colWidth),
      2: const FixedColumnWidth(_colWidth),
      if (showPromedioColumn) 3: const FixedColumnWidth(_colWidth),
    };

    // ── Header row ──────────────────────────────────────────────────────
    final headerCells = <Widget>[
      const SizedBox.shrink(),
      const RateSourceBadge(rawSource: 'bcv'),
      const RateSourceBadge(rawSource: 'paralelo'),
      if (showPromedioColumn) const _PromedioBadge(),
    ];

    final headerRow = TableRow(
      children: List<Widget>.generate(headerCells.length, (i) {
        // Header de la columna 0 está vacío pero conserva alineación
        // izquierda para coherencia con el label que va abajo.
        final align =
            i == 0 ? Alignment.centerLeft : Alignment.centerRight;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Align(alignment: align, child: headerCells[i]),
        );
      }),
    );

    // ── Data rows ────────────────────────────────────────────────────────
    final dataRows = <TableRow>[];
    for (final code in orderedCodes) {
      final group = grouped[code];
      if (group == null || group.isEmpty) continue;

      final bcvConverted = converted[(code, 'bcv')];
      final paraleloConverted = converted[(code, 'paralelo')];

      // Promedio: media de los DOS valores ya convertidos. Si falta alguno,
      // mostramos "—" (no inventamos un valor a partir de uno solo).
      final promedioRate = (bcvConverted != null && paraleloConverted != null)
          ? (bcvConverted + paraleloConverted) / 2
          : null;

      // Representative row for tap-to-edit: prefer BCV > Paralelo > first.
      final tapTarget = group.firstWhere(
        (r) => r.source == 'bcv',
        orElse: () => group.firstWhere(
          (r) => r.source == 'paralelo',
          orElse: () => group.first,
        ),
      );

      final label = '${_flagFor(code)}$code';

      final cells = <Widget>[
        // Column 0: currency label (left-aligned — aplicado en el padding
        // outer; ver builder de cells más abajo).
        GestureDetector(
          onTap: () => _edit(context, tapTarget.currencyCode),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // Column 1: BCV converted to pivot
        Text(
          _fmt(bcvConverted),
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium!.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
            color: bcvConverted == null ? dimColor : null,
          ),
        ),
        // Column 2: Paralelo converted to pivot
        Text(
          _fmt(paraleloConverted),
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium!.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
            color: paraleloConverted == null ? dimColor : null,
          ),
        ),
        // Column 3: Promedio (only rendered when column is visible)
        if (showPromedioColumn)
          Text(
            _fmt(promedioRate),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
              color: promedioRate == null ? dimColor : cs.tertiary,
            ),
          ),
      ];

      dataRows.add(
        TableRow(
          children: List<Widget>.generate(cells.length, (i) {
            // Columna 0 (label de divisa) alineada a la izquierda; las
            // columnas numéricas siguen pegadas a la derecha.
            final align =
                i == 0 ? Alignment.centerLeft : Alignment.centerRight;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Align(alignment: align, child: cells[i]),
            );
          }),
        ),
      );
    }

    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [headerRow, ...dataRows],
    );
  }

  Future<void> _edit(BuildContext context, String currencyCode) async {
    final currency = await CurrencyService.instance
        .getCurrencyByCode(currencyCode)
        .first;
    if (!context.mounted) return;
    await showManualOverrideDialog(context, initialCurrency: currency);
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
        'currencies': <String>['VES', 'EUR'],
        'sources': <String>['bcv', 'paralelo'],
        'showEvolutionChart': false,
        // null ⇒ auto-derivar el pivot (VES si está en el set efectivo,
        // si no preferredCurrency). Un código no-nulo (e.g. "USD") fuerza
        // el pivot manualmente.
        'pivotCurrency': null,
      },
      recommendedFor: const <String>{'save_usd', 'analyze'},
      builder: (context, descriptor, {required editing}) {
        final rawCurrencies = descriptor.config['currencies'];
        final currencies = rawCurrencies is List
            ? rawCurrencies.whereType<String>().toList(growable: false)
            : const <String>['VES', 'EUR'];
        final rawSources = descriptor.config['sources'];
        final sources = rawSources is List
            ? rawSources.whereType<String>().toList(growable: false)
            : const <String>['bcv', 'paralelo'];
        final rawShowChart = descriptor.config['showEvolutionChart'];
        final showChart = rawShowChart is bool ? rawShowChart : false;
        final rawPivot = descriptor.config['pivotCurrency'];
        final pivot = rawPivot is String && rawPivot.trim().isNotEmpty
            ? rawPivot
            : null;
        return KeyedSubtree(
          key: ValueKey('${descriptor.type.name}-${descriptor.instanceId}'),
          child: ExchangeRateCardWidget(
            currencies: currencies.isEmpty
                ? const <String>['VES', 'EUR']
                : currencies,
            sources: sources.isEmpty
                ? const <String>['bcv', 'paralelo']
                : sources,
            showEvolutionChart: showChart,
            pivotCurrency: pivot,
          ),
        );
      },
      configEditor: (context, descriptor) {
        // Indirección al builder mutable [exchangeRateConfigEditorBuilder].
        // Mantiene `widgets/exchange_rate_card_widget.dart` desacoplado del
        // sheet concreto (vive en `edit/`). Mismo patrón que `quickUse`.
        final builder = exchangeRateConfigEditorBuilder;
        if (builder == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Editor no inicializado. Revisa registry_bootstrap.dart.',
              ),
            ),
          );
        }
        return builder(context, descriptor);
      },
    ),
  );
}
