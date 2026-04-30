# Tasks: exchange-rate-widget-config

## Overview

Four tandas, each independently buildable. Tandas 1–2 touch only
`exchange_rate_card_widget.dart`. Tanda 3 creates the new sheet. Tanda 4
wires everything together.

---

## Tanda 1 — Bug fix + defaults (no new files, no new deps)  [x] COMPLETE

### Task 1.1 — Remove `set.remove(pref)` from `_effectiveCurrencies()`  [x]

**File:** `lib/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart`

**What to change:**
Remove these four lines from `_RatesList._effectiveCurrencies()`:

```dart
final pref = appStateSettings[SettingKey.preferredCurrency];
if (pref != null) {
  set.remove(pref);
}
```

The rest of the method (the `SingleMode` / `DualMode` policy-merge additions)
stays untouched.

Also remove the now-unused import
`package:bolsio/core/database/services/user-setting/user_setting_service.dart`
**only** if `appStateSettings` is no longer referenced anywhere else in the
file after this removal. (Check: `appStateSettings` is also referenced in
`defaults.dart` — but that is a different file. In the widget file itself,
after removal, the import is dead.)

**Acceptance criteria:**
- REQ-1: `_effectiveCurrencies()` for `currencies = ['USD', 'EUR']` and
  `preferredCurrency = USD` returns `{USD, EUR}` (not just `{EUR}`).
- REQ-1/Scenario 2: `currencies = ['EUR']` renders without crash; no
  EUR/EUR duplication.
- `flutter analyze` passes with no new warnings.

---

### Task 1.2 — Fix `defaultConfig` seed in widget spec registration  [x]

**File:** `lib/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart`

**What to change:**
In `registerExchangeRateCardWidget()`, update `defaultConfig` to use `VES`
instead of `USD` as first currency:

```dart
// Before
'currencies': <String>['USD', 'EUR'],

// After
'currencies': <String>['VES', 'EUR'],
```

Also update the fallback inside `builder:` for the empty-currencies guard:

```dart
// Before
: const <String>['USD', 'EUR'];
// (both occurrences: rawCurrencies fallback and currencies.isEmpty fallback)

// After
: const <String>['VES', 'EUR'];
```

**Acceptance criteria:**
- REQ-1/Scenario 1: a fresh descriptor built from `spec.defaultConfig` has
  `currencies == ['VES', 'EUR']`.
- No visual regression for existing users (their persisted configs are
  unchanged; the new default only applies to new descriptors).

---

### Task 1.3 — Pref-aware `exchangeRateCard` config in `defaults.dart`  [x]

**File:** `lib/app/home/dashboard_widgets/defaults.dart`

**What to change:**
1. Add import at top of file:
   ```dart
   import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
   ```
   (Check first if already imported — in the current file it is not.)

2. Add a private getter after `_quickUseFixedConfig`:
   ```dart
   static Map<String, dynamic> get _exchangeRateCardConfig {
     final pref = appStateSettings[SettingKey.preferredCurrency] as String?;
     final currencies = (pref == 'USD')
         ? <String>['VES', 'EUR']
         : <String>['USD', 'EUR'];
     return <String, dynamic>{'currencies': currencies};
   }
   ```

3. In `_buildDescriptors()`, replace:
   ```dart
   final config = type == WidgetType.quickUse
       ? _quickUseFixedConfig
       : spec.defaultConfig;
   ```
   with:
   ```dart
   final config = switch (type) {
     WidgetType.quickUse => _quickUseFixedConfig,
     WidgetType.exchangeRateCard => _exchangeRateCardConfig,
     _ => spec.defaultConfig,
   };
   ```

**Acceptance criteria:**
- REQ-2/Scenario 1: `preferredCurrency = 'USD'` → `_exchangeRateCardConfig`
  returns `{'currencies': ['VES', 'EUR']}`.
- REQ-2/Scenario 2: `preferredCurrency = 'VES'` → returns
  `{'currencies': ['USD', 'EUR']}`.
- REQ-2/Scenario 3: `preferredCurrency = 'EUR'` (or null) → returns
  `{'currencies': ['USD', 'EUR']}`.
- `flutter analyze` passes.

---

## Tanda 2 — `_PromedioRow` (pure UI, existing file only)  [x] COMPLETE

### Task 2.1 — Add `_PromedioRow` widget class  [x]

**File:** `lib/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart`

**What to change:**
Add the following class after the closing `}` of `_RateRow`:

```dart
/// Fila calculada de promedio BCV+Paralelo para VES.
/// Solo se renderiza cuando ambos rows están presentes en el snapshot.
/// Es UI pura — no escribe a la base de datos.
class _PromedioRow extends StatelessWidget {
  const _PromedioRow({
    required this.bcvRate,
    required this.paraleloRate,
  });

  final double bcvRate;
  final double paraleloRate;

  double get _promedio => (bcvRate + paraleloRate) / 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Text(
            'VES',
            style: theme.textTheme.bodyMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          // "Prom." badge — visual analogue to RateSourceBadge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: cs.tertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Prom.',
              style: theme.textTheme.labelSmall!.copyWith(
                color: cs.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Calculado',
              style: theme.textTheme.bodySmall!.copyWith(
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          Text(
            _promedio.toStringAsFixed(_promedio >= 1000 ? 0 : 2),
            style: theme.textTheme.bodyMedium!.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
```

### Task 2.2 — Wire `_PromedioRow` into `_RatesList.build()`  [x]

**File:** `lib/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart`

**What to change:**
In `_RatesList.build()`, inside the `StreamBuilder` builder callback, after
the `rows.isEmpty` guard and before the `Column` return, add promedio
detection logic. Replace the existing `Column` return with:

```dart
// Detect BCV and Paralelo rows for VES (for Promedio computation)
final wanted = _effectiveCurrencies();  // already computed above — refactor
                                         // to avoid double call: compute once
                                         // before StreamBuilder or pass in.
// NOTE: `wanted` is already in scope from line `final wanted = _effectiveCurrencies();`
// which is called OUTSIDE the StreamBuilder. No change needed there.

ExchangeRate? bcvRow;
ExchangeRate? paraleloRow;
if (wanted.contains('VES')) {
  for (final r in snapshot.data!) {
    if (r.currencyCode.toUpperCase() == 'VES') {
      if (r.source == 'bcv') bcvRow = r;
      if (r.source == 'paralelo') paraleloRow = r;
    }
  }
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
    if (bcvRow != null && paraleloRow != null) ...[
      Divider(
        height: 1,
        thickness: 0.5,
        indent: 4,
        endIndent: 4,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
      _PromedioRow(
        bcvRate: bcvRow.exchangeRate,
        paraleloRate: paraleloRow.exchangeRate,
      ),
    ],
  ],
);
```

Implementation note: `wanted` is computed before `StreamBuilder` in the
current `build()` — it stays there. The `bcvRow`/`paraleloRow` detection
runs inside the builder callback on the already-fetched snapshot.

**Acceptance criteria:**
- REQ-3/Scenario 1: When snapshot contains both `source='bcv'` and
  `source='paralelo'` rows for VES, a `_PromedioRow` appears with value
  `(bcv + paralelo) / 2`.
- REQ-3/Scenario 2: Only BCV row present → no `_PromedioRow` rendered.
- REQ-3/Scenario 3: Only Paralelo row present → no `_PromedioRow` rendered.
- No DB writes triggered. `flutter analyze` passes.

---

## Tanda 3 — `ExchangeRateConfigSheet` (new file)  [x] COMPLETE

### Task 3.1 — Create `exchange_rate_config_sheet.dart`  [x]

**File:** `lib/app/home/dashboard_widgets/edit/exchange_rate_config_sheet.dart`
(NEW — does not exist yet)

**What to create:**
A `StatefulWidget` that mirrors the `QuickUseConfigSheet` pattern but with a
single-column scrollable layout (no `TabBar`). Two visual sections:
"Mostradas" (chips with remove buttons) and "Agregar divisa" (catalog of
rate-backed currencies not yet shown).

Full implementation spec:

```dart
import 'package:flutter/material.dart';
import 'package:bolsio/app/home/dashboard_widgets/models/widget_descriptor.dart';
import 'package:bolsio/app/home/dashboard_widgets/services/dashboard_layout_service.dart';
import 'package:bolsio/core/database/services/exchange-rate/exchange_rate_service.dart';

/// Bottom sheet para configurar las divisas mostradas en un widget
/// `exchangeRateCard`. Dos secciones en columna scrollable:
///   1. **Mostradas** — chips con botón remover (×).
///   2. **Agregar divisa** — lista de divisas con tasas activas en DB,
///      excluyendo las ya mostradas; tap para añadir.
///
/// Persistencia: [DashboardLayoutService.updateConfig] en cada add/remove.
/// El debouncer del servicio coalesces los writes al disco.
class ExchangeRateConfigSheet extends StatefulWidget {
  const ExchangeRateConfigSheet({super.key, required this.descriptor});

  final WidgetDescriptor descriptor;

  @override
  State<ExchangeRateConfigSheet> createState() =>
      _ExchangeRateConfigSheetState();
}

class _ExchangeRateConfigSheetState extends State<ExchangeRateConfigSheet> {
  late List<String> _shown;

  @override
  void initState() {
    super.initState();
    _shown = _readCurrenciesFromDescriptor(widget.descriptor);
  }

  static List<String> _readCurrenciesFromDescriptor(WidgetDescriptor d) {
    final raw = d.config['currencies'];
    if (raw is! List) return <String>['VES', 'EUR'];
    final out = raw.whereType<String>().map((s) => s.toUpperCase()).toList();
    return out.isEmpty ? <String>['VES', 'EUR'] : out;
  }

  void _persist() {
    DashboardLayoutService.instance.updateConfig(
      widget.descriptor.instanceId,
      <String, dynamic>{
        ...widget.descriptor.config,
        'currencies': List<String>.unmodifiable(_shown),
      },
    );
  }

  void _addCurrency(String code) {
    if (_shown.contains(code)) return;
    setState(() => _shown.add(code));
    _persist();
  }

  void _removeCurrency(String code) {
    if (!_shown.contains(code)) return;
    setState(() => _shown.remove(code));
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // Header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Configurar divisas',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Listo'),
                ),
              ],
            ),
          ),
          // Scrollable content
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shrinkWrap: true,
              children: [
                _buildShownSection(context),
                const SizedBox(height: 16),
                _buildAddSection(context),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────── Section: Mostradas ───────────

  Widget _buildShownSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mostradas',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        if (_shown.isEmpty)
          Text(
            'No hay divisas seleccionadas.',
            style: theme.textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in _shown)
                Chip(
                  label: Text(code),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _removeCurrency(code),
                ),
            ],
          ),
      ],
    );
  }

  // ─────────── Section: Agregar divisa ───────────

  Widget _buildAddSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agregar divisa',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder(
          stream: ExchangeRateService.instance.getExchangeRates(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final available = snap.data!
                .map((r) => r.currencyCode.toUpperCase())
                .toSet()
              ..removeAll(_shown);

            if (available.isEmpty) {
              return Text(
                'Todas las divisas disponibles ya están en uso.',
                style: theme.textTheme.bodySmall,
              );
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in available.toList()..sort())
                  ActionChip(
                    label: Text(code),
                    avatar: const Icon(Icons.add, size: 16),
                    onPressed: () => _addCurrency(code),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Helper para abrir el sheet desde otros sitios de la app.
Future<void> showExchangeRateConfigSheet(
  BuildContext context, {
  required WidgetDescriptor descriptor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) => ExchangeRateConfigSheet(descriptor: descriptor),
  );
}
```

**Acceptance criteria:**
- REQ-4/Scenario 1: Tapping an `ActionChip` in "Agregar divisa" appends the
  currency to `_shown`, calls `_persist()`, and the chip moves to
  "Mostradas" immediately.
- REQ-4/Scenario 2: Tapping delete (×) on a "Mostradas" chip removes it,
  calls `_persist()`, and the chip appears in "Agregar divisa" on the next
  stream emit.
- REQ-4/Scenario 3: On app restart the updated `currencies` list is
  persisted via `DashboardLayoutService` (same persistence path as
  `QuickUseConfigSheet`).
- REQ-5/Scenario 1: A currency with no rate rows does not appear in
  "Agregar divisa" because the stream only emits currencies with actual
  rows.
- REQ-5/Scenario 2: A currency with a rate row appears in "Agregar divisa"
  (unless already shown).
- REQ-6: Independent config — each instance uses `descriptor.instanceId` in
  `updateConfig`; two instances with different configs do not cross-talk.
- `flutter analyze` passes on the new file.

---

## Tanda 4 — Wiring (`registry_bootstrap.dart` + `configEditor` in widget)  [x] COMPLETE

### Task 4.1 — Declare `exchangeRateConfigEditorBuilder` global in widget file  [x]

**File:** `lib/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart`

**What to change:**
Add at file scope (below the imports, before `class ExchangeRateCardWidget`):

```dart
/// Wired in [registerDashboardWidgets] after [registerExchangeRateCardWidget].
/// Null-safe: the configEditor lambda returns a placeholder if builder is null
/// (only affects tests that skip bootstrap).
Widget Function(BuildContext, WidgetDescriptor)? exchangeRateConfigEditorBuilder;
```

Then inside `registerExchangeRateCardWidget()`, add `configEditor` to the
`DashboardWidgetSpec(...)` constructor call:

```dart
configEditor: (context, descriptor) {
  final builder = exchangeRateConfigEditorBuilder;
  if (builder == null) {
    return const Center(child: Text('Config not wired'));
  }
  return builder(context, descriptor);
},
```

**Note:** Check the `DashboardWidgetSpec` class to confirm it has a
`configEditor` parameter. If it does not exist yet, this task must also add
the field to `DashboardWidgetSpec`. (The existing `quickUseConfigEditorBuilder`
pattern follows the same mechanism — check `quick_use_widget.dart` to confirm
the field is already on `DashboardWidgetSpec`.)

**Acceptance criteria:**
- `exchangeRateConfigEditorBuilder` is declared and accessible from
  `registry_bootstrap.dart`.
- The `configEditor` closure in the spec calls through to the builder if set.
- `flutter analyze` passes.

---

### Task 4.2 — Wire `ExchangeRateConfigSheet` in `registry_bootstrap.dart`  [x]

**File:** `lib/app/home/dashboard_widgets/registry_bootstrap.dart`

**What to change:**
1. Add import:
   ```dart
   import 'package:bolsio/app/home/dashboard_widgets/edit/exchange_rate_config_sheet.dart';
   ```

2. In `registerDashboardWidgets()`, after the call to
   `registerExchangeRateCardWidget()` (and before or after the
   `quickUseConfigEditorBuilder` assignment — order does not matter):
   ```dart
   exchangeRateConfigEditorBuilder = (context, descriptor) {
     return ExchangeRateConfigSheet(descriptor: descriptor);
   };
   ```

**Acceptance criteria:**
- After calling `registerDashboardWidgets()`, `exchangeRateConfigEditorBuilder`
  is non-null.
- The `configEditor` of the exchange rate card spec opens
  `ExchangeRateConfigSheet` when invoked from the dashboard edit mode.
- No circular import errors (`registry_bootstrap.dart` is the only file that
  imports both `exchange_rate_card_widget.dart` and
  `exchange_rate_config_sheet.dart`).
- `flutter analyze` passes.

---

## Summary table

| Tanda | Tasks | Files touched | New files |
|-------|-------|---------------|-----------|
| 1 | 1.1, 1.2, 1.3 | `exchange_rate_card_widget.dart`, `defaults.dart` | none |
| 2 | 2.1, 2.2 | `exchange_rate_card_widget.dart` | none |
| 3 | 3.1 | — | `exchange_rate_config_sheet.dart` |
| 4 | 4.1, 4.2 | `exchange_rate_card_widget.dart`, `registry_bootstrap.dart` | none |

## Decisions carried forward from design

- **ADR-1**: Remove `set.remove(pref)` — implemented in Task 1.1.
- **ADR-2**: Config sheet = two-section scrollable column — implemented in Task 3.1.
- **ADR-3**: Currency picker backed by `getExchangeRates()` stream — Task 3.1.
- **ADR-4**: `_PromedioRow` pure UI — Tasks 2.1–2.2.
- **ADR-5**: Import cycle via global builder — Tasks 4.1–4.2.
- **ADR-6**: `defaults.dart` reads `appStateSettings` synchronously — Task 1.3.
