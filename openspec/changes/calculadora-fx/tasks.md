# Tasks: calculadora-fx

## Tanda 1 — Foundation (page skeleton + routing)

- [ ] 1.1 Crear directorio `lib/app/calculator/` con subcarpetas `widgets/`, `models/`, `utils/`
- [ ] 1.2 Crear `lib/app/calculator/models/rate_source.dart` con `enum RateSource { bcv, paralelo, promedio, manual }` (UI-only, no confundir con `ExchangeRateSource` de DB) — Satisfies REQ-CALC-4
- [ ] 1.3 Crear `lib/app/calculator/calculator.page.dart` como `StatefulWidget` con `Scaffold` + AppBar (título i18n placeholder, refresh+share placeholders) y body vacío (Column placeholder). Done-when: navegable y `flutter analyze` limpio
- [ ] 1.4 Append `goToCalculator` al final de `QuickActionId` en `lib/app/home/dashboard_widgets/models/widget_descriptor.dart` (~L67, después de `openExchangeRates`). NUNCA reordenar — Satisfies REQ-CALC-8
- [ ] 1.5 Registrar entrada en `kQuickActions` dentro de `lib/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart` con `Icons.calculate_outlined`, categoría `navigation`, `action: (ctx) => RouteUtils.pushRoute(ctx, const CalculatorPage())`. NO añadir al default chip set — Satisfies REQ-CALC-8
- [ ] 1.6 Añadir entry point "Calculadora" en `lib/app/currencies/currency_manager.dart` (button cerca del rates table, sólo `RouteUtils.pushRoute`) — Satisfies REQ-CALC-9
- [ ] 1.7 Añadir `ListTile` "Calculadora" en sección utilidades de `lib/app/settings/settings_page.dart` — Satisfies REQ-CALC-9
- [ ] 1.8 `flutter analyze` limpio

## Tanda 2 — Currency panes + swap

- [ ] 2.1 Crear `lib/app/calculator/widgets/currency_amount_pane.dart`: stateless con `isActive`, `currency`, `displayValue`, `onCurrencyChanged`, `onTap` (focus pane). Currency picker via `DropdownButton` estándar — Satisfies REQ-CALC-1
- [ ] 2.2 Cablear estado en `_CalculatorPageState`: `_topCurrency = USD`, `_bottomCurrency = VES`, `_topIsActive = true` (defaults per spec) — Satisfies REQ-CALC-1
- [ ] 2.3 Renderizar dos `CurrencyAmountPane` apilados con tap → marca pane como activo (`setState`)
- [ ] 2.4 Implementar swap button (round, color desde theme/`WallexAiTokens`, ícono `Icons.swap_vert` o equiv.) entre panes; intercambia top↔bottom currencies, conserva expresión activa, alterna `_topIsActive`. Wrap en `Semantics(label: t.calculator.swap.a11y, button: true)` — Satisfies REQ-CALC-3
- [ ] 2.5 `flutter analyze` limpio

## Tanda 3 — Keypad + arithmetic

- [ ] 3.1 Crear `lib/app/calculator/widgets/calculator_keypad.dart`: grid 4×4 `7 8 9 ⌫ / 4 5 6 − / 1 2 3 + / C 0 sep =`. Recibe `onKey(KeypadKey)`. NO exponer `×` ni `÷` — Satisfies REQ-CALC-2
- [ ] 3.2 Resolver separador decimal según locale (`,` para `es-*`, `.` para `en-*`) en el keypad — Satisfies REQ-CALC-2 (Locale-aware decimal separator)
- [ ] 3.3 Estado `_activeExpression: String = '0'` en page; handler `_onKey` actualiza buffer (digit append, backspace, clear, +/-, decimal)
- [ ] 3.4 Importar y llamar `evaluateExpression(_activeExpression)` (de `lib/utils/evaluate_expression.dart`) sin wrapper; pane activo muestra resultado parseado, fallback a último valor válido si `null` — Satisfies REQ-CALC-2 (Sum before convert)
- [ ] 3.5 Helper `_effectiveRate(RateSource)`: lee `DolarApiService.instance` (`bcvRate`, `paraleloRate`), computa `(bcv+paralelo)/2` para promedio, devuelve `_manualRate` para manual
- [ ] 3.6 Pane convertido renderiza `_activeAmount * _effectiveRate` con formato locale-aware (`NumberFormat` del locale actual) — Satisfies REQ-CALC-2
- [ ] 3.7 Wrap cada keypad key en `Semantics(label: t.calculator.keypad.a11y.*, button: true)` — Satisfies REQ-CALC-11
- [ ] 3.8 `flutter analyze` limpio

## Tanda 4 — Rate sources + manual override + refresh

- [ ] 4.1 Crear `lib/app/calculator/widgets/rate_source_chip.dart`: chip con label dinámico, timestamp `hace N min`, tap cycle BCV→Paralelo→Promedio→Manual — Satisfies REQ-CALC-4
- [ ] 4.2 Cuando `_topCurrency == USDT` y source ∈ {bcv, paralelo, promedio}, label fuerza `Paralelo (USDT)` (per spec scenario "USDT label") — Satisfies REQ-CALC-4
- [ ] 4.3 `Semantics.label` del chip incluye source name + "hace N min" (timestamp leído por screen reader) — Satisfies REQ-CALC-11
- [ ] 4.4 Estado `_manualRate: double?` y `_lastFetched: DateTime?` en page; recompute converted pane synchronously al cambiar source (sin network) — Satisfies REQ-CALC-4
- [ ] 4.5 Cuando source = Manual, exponer inline `TextField` numérico (validator: > 0); `_manualRate` ephemeral, NO escribe a `exchangeRates` — Satisfies REQ-CALC-5
- [ ] 4.6 Link "Guardar como tasa manual" junto al field → abre `ExchangeRateFormDialog` pre-fill con `_manualRate` — Satisfies REQ-CALC-5 (Persist via existing dialog)
- [ ] 4.7 Cablear AppBar refresh icon + `RefreshIndicator` (pull-to-refresh): guard `if (_refreshing) return;`, llama `DolarApiService.instance.fetchAllRates()`, actualiza `_lastFetched` en éxito, snackbar non-blocking en falla — Satisfies REQ-CALC-6
- [ ] 4.8 Detectar offline first-launch sin caché (todas las rates `null` y manual no seteado): default `_source = manual`, mostrar warning inline con clave `calculator.warn.no_rate` — Satisfies REQ-CALC-1 (First launch offline scenario)
- [ ] 4.9 `flutter analyze` limpio

## Tanda 5 — Share card + render pipeline

- [ ] 5.1 Crear `lib/app/calculator/widgets/share_card.dart`: pure-render branded card (logo Wallex, conversión `$25,00 = Bs. 12.118,50`, source label, timestamp, footer "Generado con Wallex"). No estado — Satisfies REQ-CALC-7
- [ ] 5.2 Montar `ShareCard` en árbol del page bajo `Offstage(offstage: true, child: RepaintBoundary(key: _shareCardKey, child: ShareCard(...)))` con valores actuales
- [ ] 5.3 Crear `lib/app/calculator/utils/share_card_renderer.dart` con `Future<XFile?> renderShareCard(GlobalKey, BuildContext)`: cap `pixelRatio = 2.0` si `MediaQuery.shortestSide < 360`, sino `3.0`; try/catch devuelve `null` en falla — Satisfies REQ-CALC-7
- [ ] 5.4 Helper `_buildPlainTextPayload()` en page: `"$ 25,00 = Bs. 12.118,50\nParalelo · DolarApi · 27/04/2026 14:23\nGenerado con Wallex"` (locale-aware) — Satisfies REQ-CALC-7
- [ ] 5.5 Cablear AppBar share icon: render → `Share.shareXFiles([XFile], text: payload)` en éxito; en falla (renderer devuelve `null` o throw) → `Share.share(payload)` SIN toast, log a `Logger.printDebug` — Satisfies REQ-CALC-7 (Render failure falls back to text)
- [ ] 5.6 `Semantics(label: t.calculator.share.action_a11y, button: true)` en share button — Satisfies REQ-CALC-11
- [ ] 5.7 `flutter analyze` limpio

## Tanda 6 — i18n + a11y polish + smoke manual

- [ ] 6.1 Añadir bloque `calculator.*` (~15 keys) a `lib/i18n/json/en.json`: `title`, `swap.a11y`, `source.{bcv,paralelo,promedio,manual,usdt_label,updated_ago,updated_unknown}`, `manual.{field_hint,save_link}`, `warn.no_rate`, `share.{footer,action_a11y}`, `keypad.a11y.{digit,decimal,backspace,clear,plus,minus}` — Satisfies REQ-CALC-10
- [ ] 6.2 Replicar bloque equivalente en `lib/i18n/json/es.json` con traducciones VE-friendly. NO TOCAR las 8 secundarias (per `feedback_wallex_i18n_fallback`) — Satisfies REQ-CALC-10
- [ ] 6.3 Añadir `home.quick_actions.go_to_calculator: "Calculadora"` en en+es
- [ ] 6.4 Ejecutar `dart run slang` para regenerar `translations.g.dart`
- [ ] 6.5 Reemplazar todas las strings hardcoded de tandas 1-5 por `t.calculator.*` (refactor)
- [ ] 6.6 Audit a11y final: verificar swap, source chip (con timestamp), cada keypad key, share button, manual rate field tienen `Semantics.label` — Satisfies REQ-CALC-11
- [ ] 6.7 Verificar que `pubspec.yaml` y `lib/core/database/app_db.dart` no fueron modificados (`git diff` vacío en esos files) — Satisfies REQ-CALC-12
- [ ] 6.8 `flutter analyze` limpio
- [ ] 6.9 Smoke POCO rodin: ver Verification plan abajo

---

## Verification plan (smoke manual POCO rodin — Tanda 6)

Mapeo de scenarios de spec → checks manuales:

- [ ] **REQ-CALC-1** First warm cache: abrir Calculadora → top USD, bottom VES, chip Paralelo, ambos `0`
- [ ] **REQ-CALC-1** Offline cold: borrar caché + airplane mode → chip Manual, warning visible, sin crash
- [ ] **REQ-CALC-2** Locale: device es-VE → keypad muestra `,`; cambiar a en-US → muestra `.`
- [ ] **REQ-CALC-2** Sum: tipear `100 + 50` con USD/VES@100 → top `150`, bottom `15.000,00`
- [ ] **REQ-CALC-3** Swap: con top USD=100 / bottom VES=15.000 → tap swap → top VES=15.000, bottom USD=100, keystroke afecta nuevo top
- [ ] **REQ-CALC-4** Source cycle: tap chip 4 veces → BCV→Paralelo→Promedio→Manual sin network
- [ ] **REQ-CALC-4** USDT: cambiar top a USDT → chip lee "Paralelo (USDT)"
- [ ] **REQ-CALC-5** Manual ephemeral: ingresar 490, pop, reopen → chip vuelve a Paralelo, sin row en `exchangeRates` (DB Browser)
- [ ] **REQ-CALC-5** Persist link: con manual=490 → tap "Guardar como tasa manual" → `ExchangeRateFormDialog` con 490 pre-fill
- [ ] **REQ-CALC-6** Refresh: pull-to-refresh con caché stale → timestamp actualiza sin full rebuild
- [ ] **REQ-CALC-7** Share happy: conversión válida → share sheet con PNG + texto
- [ ] **REQ-CALC-7** Share fallback: forzar OOM (device viejo si disponible) o stub → fallback a `Share.share(text)` sin toast
- [ ] **REQ-CALC-8** Quick action default: upgrade build → `goToCalculator` NO en chip set; abrir `QuickUseConfigSheet` → visible para opt-in
- [ ] **REQ-CALC-8** Opt-in: enable + tap chip → abre Calculadora
- [ ] **REQ-CALC-9** Tres entry points: quick-action chip, button en `CurrencyManagerPage`, link en settings — todos abren la page
- [ ] **REQ-CALC-10** Locale `pt`: forzar device a portugués → strings `calculator.*` caen a en.json sin throw
- [ ] **REQ-CALC-11** TalkBack: focus en source chip → anuncia source + "hace N min"
- [ ] **REQ-CALC-12** `git diff pubspec.yaml` vacío; `flutter analyze` clean

---

## Notas de implementación

### Qué NO hacer (out of scope v1)

- No exponer `×` ni `÷` en keypad (engine los soporta pero UI v1 no).
- No añadir provider real Binance P2P (se traza en `usdt-binance-p2p-rate` futuro).
- No persistir manual rate como 4ta source en DB (`ExchangeRateFormDialog` ya cubre).
- No modificar el default `quickUse` chip set — opt-in only.
- No tocar las 8 locales secundarias en `lib/i18n/json/` (fallback a en.json).
- No añadir tests automatizados como gate por tanda; solo `flutter analyze` (per `feedback_flutter_tests_slow`).
- No bumpear `pubspec.yaml` ni `schemaVersion`.

### Dependencias críticas entre tandas

- Tanda 2 depende de 1.3 (page skeleton).
- Tanda 3 depende de 2.4 (swap + active pane wiring).
- Tanda 4 depende de 3.5 (`_effectiveRate` helper).
- Tanda 5 depende de 3.6 (converted amount listo para mostrar en card) y 4.x (source label + timestamp).
- Tanda 6 (i18n) puede iniciarse en paralelo con 4-5, pero el refactor 6.5 cierra al final.

### Preguntas abiertas (defer a apply)

- Iconografía exacta del swap (`Icons.swap_vert` vs `Icons.compare_arrows`).
- Color del swap button (leer de theme, no hardcodear).
- Helper de relative time existente para "hace N min" (reusar si hay).
- Estructura interna del `ShareCard` (gradiente, layout del logo).
