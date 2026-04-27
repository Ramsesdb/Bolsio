# Proposal: Calculadora FX

> Builds on `openspec/changes/calculadora-fx/explore.md`. Decisions there are locked; this proposal commits to scope and acceptance.

## Why

Wallex users in Venezuela perform ad-hoc FX conversions (USD/EUR/USDT ↔ VES) many times per day — at the store, during negotiations, splitting bills. Today the app exposes rates inside `CurrencyManagerPage` and the transaction form's `ExchangeRateSelector`, but there is no first-class surface for "just convert and tell me the number". Users open Rial or a browser, leaving Wallex for a use case it already has all the data for (DolarApi, BCV/paralelo, promedio, manual overrides). A dedicated Calculadora reuses existing plumbing and turns Wallex into the daily-driver FX surface Venezuelan users already expect.

## What changes

- New top-level `CalculatorPage` reached via `RouteUtils.pushRoute` (same pattern as `BudgetsPage`, `StatsPage`).
- Stacked top/bottom currency panes with per-pane currency picker (USD, EUR, USDT, VES + any user-enabled currency).
- Round green swap button between panes — toggles which side is active and inverts the conversion.
- Numeric keypad: `0-9`, locale-aware decimal separator (`,` es / `.` en), backspace, `C`, `+`, `−`. Reuses `evaluate_expression.dart` engine; only 2 of its 4 operators exposed in v1.
- Rate source chip cycling BCV ↔ Paralelo ↔ Promedio ↔ Manual, with last-fetch timestamp ("hace 12 min").
- Manual rate: inline numeric field, ephemeral (no DB write). Adjacent "Guardar como tasa manual" link opens existing `ExchangeRateFormDialog` pre-filled for users wanting persistence.
- USDT in v1 = alias of paralelo, labeled "Paralelo (USDT)" so the user knows the source.
- Refresh action calls `DolarApiService.instance.fetchAll()`; pull-to-refresh + AppBar icon.
- Share action: render branded card via `RepaintBoundary.toImage(pixelRatio: 3)` → temp PNG → `Share.shareXFiles` with plain-text companion. Fallback to `Share.share(plainText)` on render failure.
- New `goToCalculator` entry in `QuickActionId` (appended at end; enum order is persisted in layout JSON) and registered in `kQuickActions` under `QuickActionCategory.navigation` with `Icons.calculate_outlined`. **Default OFF** in initial chip set — opt-in via `QuickUseConfigSheet`.
- Secondary entry points: small "Calculadora" button in `CurrencyManagerPage` rates table + settings menu link. Three discovery surfaces, zero forced layout migration.
- New `calculator.*` i18n keys in `en.json` and `es.json` only (per memory `feedback_wallex_i18n_fallback`).

## Out of scope (v1)

- Multiplication and division operators (`×`, `÷`).
- Real Binance P2P USDT provider — defer to a separate `usdt-binance-p2p-rate` change.
- Persisted manual rate as a 4th DB source — existing `ExchangeRateFormDialog` already covers that.
- Historical rates per date (rate is "now-only").
- History list of recent conversions ("últimas 5").
- Dashboard mini-widget that shows live conversion (calculator stays a destination, not a tile).
- Voice input.
- Re-skin / brand variants of the share card (one templated card).
- New pub dependencies (`share_plus ^12.0.1` already present; `RenderRepaintBoundary` is SDK-built-in).
- Drift schema migration.

## Stakeholders / impact

- **End users (VE)** — Primary beneficiary. Faster everyday FX conversions, less app switching.
- **Dashboard / quick-actions system** — Touched: `widget_descriptor.dart` (enum append) + `quick_action_dispatcher.dart` (catalog entry). No layout-JSON migration because the enum is appended, not reordered.
- **Currency manager surface** — Adds one entry-point button; no behavior change in the page itself.
- **DolarApiService + RateProviderManager** — Reused as-is; the calculator becomes a new consumer, not a new provider.
- **Share / brand surface** — First user-generated branded artifact. Soft brand exposure when shared on WhatsApp / Telegram. No backend.
- **i18n** — Only `en.json` + `es.json` modified; the 8 secondary locales fall through to `en.json` per the existing slang convention.

## Acceptance criteria

- Landing on Calculadora and converting `USD → VES`, `VES → USD`, or `EUR → VES` takes ≤3 taps from a keyed-in amount.
- Switching rate source (BCV / Paralelo / Promedio / Manual) updates the converted amount instantly with no network round-trip when the cache is warm.
- Refresh action invokes `DolarApiService.fetchAll()` and updates the timestamp label without rebuilding the page.
- Manual rate selection accepts an ephemeral value, applies it to all conversions in the session, and is discarded on page exit (verified by reopening the page → defaults to Paralelo).
- Share action emits an OS share-sheet entry containing a PNG card AND a plain-text companion payload; render failure falls back to plain text without surfacing an error toast.
- Calculator is reachable from ≥3 entry points: opt-in quick-action chip, `CurrencyManagerPage` rates table button, settings menu.
- Default `quickUse` chip set is unchanged for existing users; `goToCalculator` is visible only inside `QuickUseConfigSheet` until opted in.
- `flutter analyze` is clean; existing persisted dashboard layout JSON parses without migration.
- New i18n keys exist in `en.json` and `es.json`; the 8 secondary locales are untouched.
- No `exchangeRates` row is ever written by the calculator (manual rate stays in memory).
- No new entry in `pubspec.yaml`.

## Open questions

None blocking. Q1–Q6 are answered in `explore.md` and locked here. The single residual lookahead — whether to lift the EUR rate-limit retry into a shared helper — is a follow-up captured in Risk #2 below, not a v1 blocker.

## Risks (top 3, unchanged from explore)

1. **Stale rates / offline first-launch** — Degrade to "Manual" mode with a non-blocking inline warning when no cached rate exists; never block the UI on the network call.
2. **Share-card render on low-end devices** — Cap `pixelRatio` at 2× for screens <360 dp; on render failure, fall back to plain-text share.
3. **USDT ≠ paralelo during devaluation spikes** — Mitigated by labeling the source "Paralelo (USDT)" in v1; real USDT provider tracked as a separate future change.

See `explore.md` §Risks for the full 8-item list (rate-limit retry, manual-field UX on small screens, enum-ordering safety, etc.) — all carried forward, none escalating to blockers.
