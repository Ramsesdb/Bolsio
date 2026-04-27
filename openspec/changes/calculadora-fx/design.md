# Design: calculadora-fx

> Builds on `proposal.md` (locked) and `specs/calculator/spec.md`. This is a thin technical mapping: no architectural unknowns, no schema migration, no new pub deps.

## Resumen de arquitectura

`CalculatorPage` es un `StatefulWidget` standalone que orquesta tres widgets visuales (`CurrencyAmountPane` x2, `CalculatorKeypad`, `RateSourceChip`) sobre el singleton `DolarApiService.instance` y el evaluador puro `evaluate_expression.dart`. Toda la conversión vive en el estado del page (no se introduce un service nuevo): el page mantiene la expresión activa, parsea el monto vía `evaluate_expression` y deriva el valor convertido aplicando la tasa actual del source seleccionado. El share usa `RepaintBoundary.toImage` sobre un `ShareCard` montado off-screen, escribe un PNG temporal y delega a `share_plus`. El page se alcanza vía `RouteUtils.pushRoute(const CalculatorPage())` desde tres entry points (quick action opt-in, `CurrencyManagerPage`, settings).

---

## Decisiones de arquitectura

### 1. Estado en el page, no en un service

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| `CalculatorService` singleton (como `DolarApiService`) | Sobre-ingeniería: no hay state cross-screen ni persistencia | Rechazada |
| `ChangeNotifier`/`Provider` page-scoped | Añade dependencia de árbol para 5 fields efímeros | Rechazada |
| `StatefulWidget` con `setState` | Minimal, todo el estado muere al pop | **Elegida** |

**Rationale**: el manual rate y la expresión son ephemeral por contrato (spec). No hay otro consumidor del estado del calculator. `setState` es el costo más bajo y se alinea con `BudgetsPage`/`StatsPage`.

### 2. Reuso del engine `evaluate_expression.dart` sin wrapper

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| Crear `CalculatorEngine` envoltorio | Duplica API; el engine ya es puro y testeado | Rechazada |
| Llamar `evaluateExpression(expr)` directamente desde el page | Cero indirección | **Elegida** |

**Rationale**: el engine ya exporta `evaluateExpression(String) → double?`. Solo se exponen 2 de 4 operadores en el keypad — el engine acepta todos pero la UI nunca emite `×` ni `÷`. No requiere cambios en `evaluate_expression.dart`.

### 3. Render del share card off-screen

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| Modal full-screen con preview + botón share | Dos taps, viola "≤3 taps" del proposal | Rechazada |
| `RepaintBoundary` montado siempre como `Offstage` en el page | Render path ya warmed-up al pulsar share | **Elegida** |
| `OverlayEntry` ad-hoc al pulsar | Race con primer frame del overlay | Rechazada |

**Rationale**: el `ShareCard` se monta dentro del árbol del page bajo `Offstage(offstage: true)` con `RepaintBoundary` y un `GlobalKey`. Al pulsar share, `key.currentContext.findRenderObject() as RenderRepaintBoundary` captura el frame existente — sin reparent ni doble render.

### 4. Manual rate en estado local, persistencia delegada al diálogo existente

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| Persistir como 4ta source en `exchangeRates` | Pollute DB con rates throwaway; nuevo `RateSource` enum | Rechazada |
| Estado `double? _manualRate` en el page | Cero acoplamiento con DB | **Elegida** |
| Botón "Guardar como tasa manual" → `ExchangeRateFormDialog` pre-fill | Reuso explícito del flujo persistente | **Elegida** |

---

## Plan de archivos

| Archivo | Acción | Qué hace |
|---------|--------|---------|
| `lib/app/calculator/calculator.page.dart` | Crear | Page raíz: `Scaffold` con AppBar (refresh + share), 2 `CurrencyAmountPane` apilados, swap button entre ellos, `RateSourceChip`, `CalculatorKeypad`, `Offstage(ShareCard)`. Sostiene todo el estado. |
| `lib/app/calculator/widgets/currency_amount_pane.dart` | Crear | Pane con currency picker (dropdown/sheet) + monto display. Recibe `isActive`, `currency`, `displayValue`, `onCurrencyChanged`. |
| `lib/app/calculator/widgets/calculator_keypad.dart` | Crear | Grid 4×4: `7 8 9 ⌫ / 4 5 6 − / 1 2 3 + / C 0 sep =`. Recibe `onKey(KeypadKey)`. Sep = `,` o `.` según locale. |
| `lib/app/calculator/widgets/rate_source_chip.dart` | Crear | Chip cycling BCV→Paralelo→Promedio→Manual con timestamp `hace N min`. Cuando source = Manual, expone inline `TextField` numérico + link "Guardar como tasa manual". |
| `lib/app/calculator/widgets/share_card.dart` | Crear | Card branded (logo, conversión, source label, timestamp, "Generado con Wallex"). Pure-render, sin estado. |
| `lib/app/calculator/utils/share_card_renderer.dart` | Crear | Helper `Future<XFile?> renderShareCard(GlobalKey, {double pixelRatio})` con try/catch + cap 2× para `shortestSide < 360`. Devuelve `null` en falla; el page hace fallback a `Share.share(plainText)`. |
| `lib/app/home/dashboard_widgets/models/widget_descriptor.dart` | Modificar | Append `goToCalculator` al final de `QuickActionId` (línea ~67, después de `openExchangeRates`). NUNCA reordenar — los `name` están persistidos en layout JSON. |
| `lib/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart` | Modificar | Añadir entrada en `kQuickActions` bajo `QuickActionCategory.navigation` con `Icons.calculate_outlined`, label desde slang, `action: (ctx) => RouteUtils.pushRoute(ctx, const CalculatorPage())`. Importar `CalculatorPage`. |
| `lib/app/currencies/currency_manager.dart` | Modificar | Añadir `IconButton`/`TextButton` "Calculadora" cerca del rates table que llame `RouteUtils.pushRoute`. Solo entry point — no toca el resto. |
| `lib/app/settings/settings_page.dart` | Modificar | Una `ListTile` "Calculadora" en sección utilidades. |
| `lib/i18n/json/en.json` | Modificar | Añadir bloque `calculator.*` (~15 keys, abajo). |
| `lib/i18n/json/es.json` | Modificar | Equivalente español. **NO tocar las 8 secundarias** (per `feedback_wallex_i18n_fallback`). |
| `pubspec.yaml` | NO TOCAR | `share_plus ^12.0.1` ya presente; `RepaintBoundary` es SDK. |
| `lib/core/database/app_db.dart` | NO TOCAR | Sin migración. |

---

## Modelo de estado

`CalculatorPageState` (StatefulWidget):

```
class _CalculatorPageState extends State<CalculatorPage> {
  // Currencies
  Currency _topCurrency = USD;    // default per spec
  Currency _bottomCurrency = VES;
  bool _topIsActive = true;        // which pane the keypad targets

  // Amount entry
  String _activeExpression = '0'; // raw buffer fed to evaluate_expression
  // (parsed on every rebuild, no separate cached field)

  // Rate source
  RateSource _source = RateSource.paralelo;
  double? _manualRate;             // ephemeral; null when not in Manual
  DateTime? _lastFetched;          // mirrored from DolarApiService at build

  // Share
  final GlobalKey _shareCardKey = GlobalKey();

  // UI feedback
  bool _refreshing = false;
}
```

Computed (no fields):
- `double _activeAmount` = `evaluateExpression(_activeExpression) ?? 0`
- `double _convertedAmount` = `_activeAmount * _effectiveRate(top→bottom direction)`
- `_effectiveRate` reads `DolarApiService.instance` for BCV/Paralelo, computes `(bcv + paralelo)/2` for Promedio, uses `_manualRate` for Manual.

`RateSource` enum vive en el page o en `lib/app/calculator/models/rate_source.dart` (4 values: bcv, paralelo, promedio, manual). NO es el mismo que `ExchangeRateSource` de la DB — este es UI-only.

---

## Flujo de datos

```
Keypad tap ──► _activeExpression += digit ──► setState
                                                  │
                                                  ▼
                                evaluateExpression(_activeExpression)
                                                  │
                                                  ▼
                          activePane shows _activeAmount, formatted
                                                  │
                                                  ▼
                          convertedPane shows _activeAmount * rate
```

```
Source chip tap ──► _source = next(_source) ──► setState
                                                   │
                                                   ▼
                                  rebuild reads new _effectiveRate
                                  (sync, no network — uses cached
                                   DolarApiService.instance.*Rate)
```

```
Refresh tap / pull ──► _refreshing = true ──► setState
                            │
                            ▼
                DolarApiService.instance.fetchAllRates()
                            │
                ┌───────────┴───────────┐
            success                  failure
                │                       │
                ▼                       ▼
        _lastFetched=now      keep prev rates
        _refreshing=false      ScaffoldMessenger
        setState               (non-blocking toast)
```

```
Swap tap ──► temp = top; _topCurrency = bottom; _bottomCurrency = temp
              _topIsActive = !_topIsActive
              _activeExpression preserved (moves with active pane)
              setState
```

---

## Render del share card

Flujo cuando user pulsa share (AppBar):

1. `final boundary = _shareCardKey.currentContext.findRenderObject() as RenderRepaintBoundary;`
2. `final ratio = MediaQuery.of(context).size.shortestSide < 360 ? 2.0 : 3.0;`
3. `final image = await boundary.toImage(pixelRatio: ratio);`
4. `final bytes = await image.toByteData(format: ImageByteFormat.png);`
5. Write `bytes` a `${getTemporaryDirectory()}/wallex_calc_${ts}.png`.
6. `Share.shareXFiles([XFile(path)], text: _buildPlainTextPayload())`.
7. Cualquier excepción en pasos 1-5 → `Share.share(_buildPlainTextPayload())`. NO toast (per spec). Log a `Logger.printDebug`.

`_buildPlainTextPayload()` formato:
```
$ 25,00 = Bs. 12.118,50
Paralelo · DolarApi · 27/04/2026 14:23
Generado con Wallex
```

`ShareCard` se monta una sola vez en el árbol bajo `Offstage(offstage: true, child: RepaintBoundary(key: _shareCardKey, child: ShareCard(...)))` con los valores actuales — `Offstage` lo deja fuera del layout pero `RepaintBoundary` mantiene la layer paintada para captura.

---

## Wiring del quick action

**`widget_descriptor.dart` (~L67)** — append:
```dart
enum QuickActionId {
  togglePrivateMode,
  // ... existentes ...
  openExchangeRates,
  goToCalculator;   // ← NEW, al final
  // ...
}
```

**`quick_action_dispatcher.dart`** — añadir entrada en `kQuickActions`:
```dart
QuickActionId.goToCalculator: QuickAction(
  icon: Icons.calculate_outlined,
  label: (ctx) => Translations.of(ctx).home.quick_actions.go_to_calculator,
  category: QuickActionCategory.navigation,
  action: (ctx) => RouteUtils.pushRoute(ctx, const CalculatorPage()),
),
```

**Default chip set**: NO modificar. El chip aparece solo en `QuickUseConfigSheet` para opt-in (per spec — el dispatcher ya filtra por presencia en el set persistido).

---

## Claves i18n (en.json / es.json)

Namespace `calculator.*`. Lista representativa (~15 keys; los traduce `sdd-tasks`/`sdd-apply`):

```json
"calculator": {
  "title": "Calculadora",
  "swap.a11y": "Invertir conversión",
  "source": {
    "bcv": "BCV",
    "paralelo": "Paralelo",
    "promedio": "Promedio",
    "manual": "Manual",
    "usdt_label": "Paralelo (USDT)",
    "updated_ago": "hace {minutes} min",
    "updated_unknown": "—"
  },
  "manual": {
    "field_hint": "Tasa por 1 USD",
    "save_link": "Guardar como tasa manual"
  },
  "warn": {
    "no_rate": "Sin tasa en caché. Usa el modo Manual o conéctate."
  },
  "share": {
    "footer": "Generado con Wallex",
    "action_a11y": "Compartir conversión"
  },
  "keypad.a11y": {
    "digit": "Dígito {n}",
    "decimal": "Separador decimal",
    "backspace": "Borrar",
    "clear": "Limpiar",
    "plus": "Sumar",
    "minus": "Restar"
  }
}
```

`home.quick_actions.go_to_calculator: "Calculadora"` se añade en el catálogo existente.

**Comando post-edición**: `dart run slang`.

---

## Accesibilidad

| Control | Semantics |
|---------|-----------|
| Swap button | `Semantics(label: t.calculator.swap.a11y, button: true)` |
| Source chip | `Semantics(label: "${sourceName} · ${updatedAgoText}", button: true)` — **incluye el timestamp** para que screen reader lo lea |
| Each keypad key | `Semantics.label` desde `calculator.keypad.a11y.*`, `button: true` |
| Share button | `Semantics(label: t.calculator.share.action_a11y, button: true)` |
| Share output | `Share.shareXFiles(text:)` siempre incluido — los share targets "Save text" reciben el payload textual |
| Currency picker per pane | usa `DropdownButton` estándar (a11y nativo Flutter) |
| Manual rate field | `TextField` con `decoration.labelText` + `keyboardType: numberWithOptions` |

---

## Edge cases / failure modes

| Caso | Comportamiento |
|------|---------------|
| Offline first launch, sin caché | `_source = manual`, mostrar `calculator.warn.no_rate`, page renderiza sin throw (per spec scenario "First launch offline with no cache") |
| `evaluateExpression` devuelve `null` (expresión inválida transitoria, ej. "100+") | Active pane muestra `0` o último valor parseado — NO mostrar error; el siguiente keystroke completa la expresión |
| División por cero | N/A en v1 (`÷` no expuesto); el engine soporta operadores no expuestos sin riesgo |
| Overflow aritmético en montos enormes | `double.infinity` → formateamos como `—` y bottom pane muestra placeholder. No throw |
| `RepaintBoundary.toImage` OOM en device viejo | Catch → fallback a `Share.share(plainText)` sin toast |
| Refresh durante refresh (doble tap) | `if (_refreshing) return;` guard al inicio del handler |
| Manual rate = 0 o negativo | Rechazar en el `TextField` validator; bottom pane mantiene último valor válido |
| Currency picker selecciona la misma currency en ambos panes | Permitido (rate = 1); evita branch especial |
| Pop con manual activo | State se descarta automáticamente (StatefulWidget); reopen → default Paralelo (per spec) |
| Locale `pt`/otros | Todas las strings nuevas caen a `en.json` (slang base-locale fallback, per memory) |

---

## No-decisiones (defer a apply)

- **Iconografía exacta** del swap button — `Icons.swap_vert` vs `Icons.compare_arrows` queda a criterio del implementador siguiendo el sistema de iconos existente.
- **Curva de animación** del swap (`Tween` vs `AnimatedSwitcher`) — visual polish.
- **Spacing/padding** específico de cada pane — ajustar al diseño Material que use el resto de Wallex (`AppLayoutContants` si aplica).
- **Color exacto** del swap button verde — leer del theme/`WallexAiTokens` o equivalente; no hardcodear hex (per memoria `project_wallex_ai_chat_v2`).
- **Forma del timestamp** ("hace 12 min" vs "Actualizado 12 min") — usar el helper de relative time existente en el proyecto si lo hay.
- **Estructura interna del `ShareCard`** (gradiente, layout exacto del logo) — mientras incluya los campos requeridos por spec.

---

## Plan de testing

| Capa | Qué probar | Enfoque |
|------|-----------|---------|
| Unit | `evaluateExpression` (ya existe `test/evaluate_expression_test.dart`) | Reuso, no añadir |
| Unit | Helper que mapea `RateSource → double` desde `DolarApiService` mock | Nuevo, fixtures simples |
| Widget | `CalculatorPage` con `DolarApiService` stubbed: typing → swap → source cycle | Smoke |
| Widget | Offline first-launch → defaults a Manual + warning visible | Scenario spec |
| Manual | Share happy path en POCO rodin | Checklist QA |
| Manual | Share render falla en device viejo → cae a texto | Checklist QA (per memoria `project_wallex_build_optimal`) |
| Skip | `flutter test` full suite per memoria `feedback_flutter_tests_slow` — solo `flutter analyze` por tanda |

---

## Preguntas abiertas

Ninguna bloqueante. Riesgos #1-#3 del proposal heredados sin escalación.
