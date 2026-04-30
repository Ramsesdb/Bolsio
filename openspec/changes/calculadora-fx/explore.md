# Exploration: calculadora-fx

> Phase: explore. No code changes. Inspired by the Venezuelan finance app **Rial**: a fast in-pocket FX calculator that lets the user move between USD/EUR/USDT and VES with the live BCV / paralelo / promedio rate, optionally overriding it manually, and share the result as a branded card.

---

## Problem statement

Bolsio users in Venezuela do quick FX conversions multiple times per day (price tags in stores, tipping, paying in dollars vs bolivares). Today the app exposes rates inside `CurrencyManagerPage` and inside the transaction form's `ExchangeRateSelector`, but there is no first-class "Calculadora" surface: no large amount display, no numeric keypad, no swap button, no "share this conversion" affordance. Users open Rial or a browser instead. Bolsio already has the data plumbing (DolarApi, BCV/paralelo, promedio, manual overrides, source-aware queries) but no presentation layer dedicated to ad-hoc conversions outside of a transaction.

## User stories

1. **Quick price check** — As a shopper looking at a Bs. price tag, I want to type the bolivar amount and instantly see the equivalent USD/EUR using either BCV or paralelo so I can decide whether to pay in cash or transfer.
2. **Reverse conversion** — As someone budgeting in USD, I want to type a USD amount and see the bolivar equivalent at paralelo rate, and swap source/target with one tap.
3. **Manual rate** — As a freelancer who just agreed on a custom rate (e.g. 490 Bs/USD with a client), I want to override the rate in the calculator without touching the global app rate, do a few conversions at that rate, and discard it on close.
4. **Arithmetic before convert** — As a user splitting a Bs. 1.450 + 320 + 75 bill, I want to type "1450 + 320 + 75" inside the calculator and see the converted total, without leaving the screen.
5. **Share the result** — As a user negotiating a payment over WhatsApp, I want to share the conversion ("$ 25.00 = Bs. 12.118,50 al paralelo, 27/04/2026") as a branded image card so the counterpart trusts the source.
6. **Discoverable from dashboard** — As a regular user, I want a "Calculadora" quick-action chip I can pin to the dashboard's `quickUse` widget, opening the calculator in one tap.

## Affected systems / files (verified)

### New
- `lib/app/calculator/calculator.page.dart` — top-level page (the hub).
- `lib/app/calculator/widgets/currency_amount_pane.dart` — the stacked top/bottom currency selector + amount display.
- `lib/app/calculator/widgets/calculator_keypad.dart` — keypad (digits, comma, backspace, C, +/−).
- `lib/app/calculator/widgets/rate_source_chip.dart` — BCV / Paralelo / Promedio / Manual selector, with last-fetch timestamp.
- `lib/app/calculator/widgets/share_card.dart` — RepaintBoundary widget the share action snapshots to PNG.
- `lib/app/calculator/services/calculator_engine.dart` — pure-Dart input buffer + arithmetic evaluator (or thin wrapper around the existing `evaluate_expression.dart`).
- `lib/i18n/json/en.json`, `lib/i18n/json/es.json` — `calculator.*` keys (per memory note `feedback_bolsio_i18n_fallback`: only en + es; do NOT touch the 8 secondary locales).

### Touched (existing)
- `lib/app/home/dashboard_widgets/models/widget_descriptor.dart` (~L56) — add `goToCalculator` to `QuickActionId` enum.
- `lib/app/home/dashboard_widgets/widgets/quick_use/quick_action_dispatcher.dart` (~L71) — register `goToCalculator` entry in `kQuickActions` (category: `navigation`).

### Reused (no changes expected)
- `lib/core/services/dolar_api_service.dart` — `DolarApiService.instance` (singleton, 1-hour `isStale`, holds `oficialRate` / `paraleloRate` / `eurOficialRate` / `eurParaleloRate`). This is the right entry point for the calculator: reuse the cached promedio values and `fetchAll()` on stale.
- `lib/core/services/rate_providers/rate_provider_manager.dart` — fallback chain (currently single provider, but the abstraction is already there).
- `lib/core/database/services/exchange-rate/exchange_rate_service.dart` — source-aware queries; ONLY relevant if we decide to persist Manual as a 4th source (see Q3 below).
- `lib/app/transactions/form/dialogs/evaluate_expression.dart` — defines `CalculatorOperator` enum (`add/subtract/multiply/divide`). Already battle-tested + has `test/evaluate_expression_test.dart`. If we go full arithmetic this is the engine to reuse, **even though** the current Rial-style mockup only shows `+` and `−`.
- `package:share_plus` — already in `pubspec.yaml` (`^12.0.1`). No new dep needed.
- `RenderRepaintBoundary` (Flutter SDK) — render-to-image is built in; no extra package required.
- `lib/core/routes/route_utils.dart` — `RouteUtils.pushRoute` is the standard navigation pattern (used by every other quick action).

### Not affected (explicit out-of-scope)
- Drift schema. No migration.
- `ExchangeRateFormDialog`. The calculator's manual rate stays ephemeral (see Q3).
- `RateProviderManager` provider list. Reuse as-is.

---

## Recommended scope (v1)

### IN
- Single new page `CalculatorPage` reachable via `RouteUtils.pushRoute`.
- Two stacked currency panes (top + bottom). Currency picker per pane: USD, EUR, USDT, VES (and any other currency the user has enabled in `CurrencyManager`, but **the green swap button always maps top↔bottom** — no triangulation).
- Live amount display on whichever pane is "active" (the one being typed into); the other pane shows the converted value, read-only.
- Round green swap button between the panes (swaps which side is active and inverts the conversion).
- Numeric keypad: `0-9`, decimal separator (locale-aware: `,` in es, `.` in en), backspace, `C` (clear), `+`, `−`. **No `×` `÷` in v1** to match Rial's screenshot — keep it minimal. (See Q1.)
- Rate source chip below: cycles BCV ↔ Paralelo ↔ Promedio ↔ Manual. Promedio computed as `(BCV + Paralelo) / 2` reusing the formula already in `exchange_rate_card_widget.dart` (~L77-82).
- Manual rate: a small inline numeric field that appears when the user picks "Manual"; ephemeral (lives only for the calculator session, NOT persisted).
- Last-updated timestamp shown next to source chip ("hace 12 min", localized).
- Pull-to-refresh OR explicit refresh icon to call `DolarApiService.instance.fetchAll()`.
- Share action in the AppBar: renders a branded card via `RepaintBoundary → toImage → PNG` and hands it to `Share.shareXFiles`. Fallback to plain text when image render fails.
- New `goToCalculator` quick action in the catalog. **Default OFF** in initial chip set (per the user's hint) — discoverable only by users who opt in via `QuickUseConfigSheet`.

### OUT (deferred)
- Multiplication/division.
- Persisted manual rate (use existing `ExchangeRateFormDialog` route if the user wants persistence).
- USDT pulled from a Binance P2P API (USDT in v1 is just an alias of paralelo; see Q2).
- History of recent conversions ("últimas 5").
- Currency calculator widget on the dashboard (it stays as a destination, not a tile).
- Voice input.
- Re-skin / branding overhaul of the share card (one templated card is enough for v1).

---

## Open questions, answered

### Q1 — Calculator depth: full arithmetic or plain numeric?
**Recommendation: plain numeric + `+` and `−` only**, no `×` `÷`.
- Rial's screenshot only shows `+ −`, and the use case is "add up the bill before converting", which `+` covers fully.
- Keeps the keypad to a 4×4 grid: `7 8 9 ⌫ / 4 5 6 − / 1 2 3 + / C 0 , =`.
- The arithmetic engine is `lib/app/transactions/form/dialogs/evaluate_expression.dart` (`CalculatorOperator`) reused, but we only expose 2 of its 4 operators in the UI. No code change needed in the engine.
- If users ask for `×` `÷` later, we expose them — incremental, low cost.

### Q2 — USDT as a source: alias of paralelo, or separate provider?
**Recommendation: alias of paralelo for v1.**
- DolarApi's `paralelo` rate already tracks USDT P2P closely in practice (paralelo IS the dollar street price, which in VE is functionally USDT/VES).
- A real Binance P2P provider means a new `RateProvider` implementation, P2P API auth/scraping, and dealing with Binance's anti-bot. Out of v1 scope.
- UX: USDT shows the same numeric value as USD-paralelo, but the rate source chip shows "Paralelo (USDT)" so the user knows what they're seeing.
- Defer real USDT provider to a separate `usdt-binance-p2p-rate` change once the calculator is shipped.

### Q3 — Manual rate: persisted as 4th source, or ephemeral in-screen?
**Recommendation: ephemeral.**
- The existing `ExchangeRateFormDialog` (`lib/app/currencies/exchange_rate_form.dart`) already covers persisted manual rates — there's no need to duplicate it.
- The Rial use case for manual rate IS ephemeral (negotiated rate for one transaction, not a global app override).
- Keeps the calculator stateless: no DB writes, no risk of polluting `exchangeRates` with throwaway numbers.
- Provide a "Guardar como tasa manual" link/button next to the manual field that opens `ExchangeRateFormDialog` pre-filled — gives users an explicit upgrade path without coupling the screens.

### Q4 — Share card: branded image or plain text?
**Recommendation: branded image with plain-text fallback.**
- `share_plus ^12.0.1` is already in `pubspec.yaml`, supports `shareXFiles`.
- Flutter's `RenderRepaintBoundary.toImage(pixelRatio: 3)` → `ByteData` → temp file is the standard pattern; no extra package.
- The card includes: Bolsio logo, the conversion ("$ 25.00 ⇄ Bs. 12.118,50"), source ("Paralelo · DolarApi"), timestamp, and a small "Generado con Bolsio" footer. Acts as soft brand exposure.
- **Fallback path**: if rendering fails (low memory, headless render race), call `Share.share(plainText)` instead — never silently fail.
- A11y: the rendered card must have a textual `Share.shareXFiles(text:)` companion so screen readers and "Save text" share targets get the same content.

### Q5 — Quick action integration
**Recommendation: confirmed — add `goToCalculator` to enum + dispatcher; NOT in default chip set.**
- Add to `QuickActionId` enum at `lib/app/home/dashboard_widgets/models/widget_descriptor.dart` (~L56) — append at the end (avoid reordering, the enum names are persisted in dashboard layout JSON).
- Register in `kQuickActions` map in `quick_action_dispatcher.dart` with `category: QuickActionCategory.navigation`, icon `Icons.calculate_outlined`.
- Don't add to the default `quickUse` chip set — let users opt in via `QuickUseConfigSheet` so we don't churn existing dashboards.
- Also expose entry points from: `CurrencyManagerPage` (a small "Calculadora" button next to the rates table) and the settings menu — gives 3 discovery surfaces without forcing layout migration.

### Q6 — Routing
**Recommendation: `RouteUtils.pushRoute(const CalculatorPage())`.** Same pattern every other top-level page uses (`SettingsPage`, `BudgetsPage`, `StatsPage`, `CurrencyManagerPage`). No router config changes.

---

## Risks & unknowns

1. **Stale rates / offline behavior** — `DolarApiService.isStale` triggers at 1 hour. If the user is offline the calculator shows the last-cached rate with a "actualizado hace N horas" label; if there is no cached rate at all (first launch offline), we degrade to "Manual" mode and surface a non-blocking inline warning. Don't block the UI on the network call.
2. **EUR rate-limiting** — `exchange_rate_card_widget.dart` already comments that EUR endpoints rate-limit after multiple calls; the fallback retry pattern there should be lifted into a shared helper (or we accept the same retry-on-fetch pattern here). Track for follow-up.
3. **USDT vs paralelo divergence** — In normal market conditions paralelo ≈ USDT P2P, but during stress events (devaluation spikes) they can diverge by 5–8 %. Labeling it explicitly as "Paralelo (USDT)" mitigates user confusion; a real USDT provider remains the right long-term answer.
4. **Share card render on low-end devices** — POCO rodin is fine, but a 3× pixel ratio render of a full-card layout could OOM on very old devices. Mitigation: cap pixel ratio at 2× for screens <360 dp, or detect and degrade to plain text. Cover in test plan.
5. **Share card a11y / OCR-resistance** — Pure-image cards are invisible to screen readers and to copy/paste. Always pair the image with a text payload (`Share.shareXFiles(files: [...], text: '...')`).
6. **Locale-aware decimal separator** — Keypad must show `,` for `es-VE` and `.` for `en-US`. Bolsio uses `intl.NumberFormat` already; reuse the existing pattern — don't roll new locale logic.
7. **Manual rate input UX** — A small inline field is risky on small screens (keyboard occlusion). If the keypad is custom (no system keyboard), the manual rate field should reuse the calculator keypad rather than popping the system keyboard.
8. **Quick action enum ordering** — `QuickActionId` values are persisted by `name` in dashboard layout JSON. Adding `goToCalculator` at the end is safe; never reorder existing entries.

---

## Success criteria

- New `CalculatorPage` is reachable from at least 3 entry points (quick-action chip when opted in, `CurrencyManagerPage`, settings menu).
- User can complete USD→VES, VES→USD, EUR→VES round-trips in <3 taps after landing on the page.
- Source switch (BCV / Paralelo / Promedio / Manual) updates the converted amount instantly with no network round-trip when cached.
- Refresh action calls `DolarApiService.fetchAll()` and updates the timestamp label without rebuilding the entire page.
- Share action produces a PNG card opened in the OS share sheet, with a plain-text companion payload.
- Manual rate is ephemeral and never writes to `exchangeRates`.
- New i18n keys present in `en.json` and `es.json` only; `flutter analyze` clean; existing dashboard layout JSON parses untouched.
- No new pub dependency.
- Quick action does not appear in default chip set; appears in `QuickUseConfigSheet` catalog under "Navigation".

---

## Ready for proposal

**Yes.** Recommendations are concrete and reuse existing infra (DolarApiService, share_plus, evaluate_expression, RouteUtils). No schema migrations. The only architectural decision left for `sdd-propose` to lock in is whether to keep `+/−` only or include `×/÷` — recommendation above is `+/−` only.
