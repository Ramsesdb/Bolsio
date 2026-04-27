# Calculator Specification

## Purpose

Define the behavior of a first-class FX Calculadora page that converts amounts between user-enabled currencies (USD, EUR, USDT, VES, plus any enabled in CurrencyManager) using existing rate sources, with arithmetic, ephemeral manual rate, branded share, and opt-in dashboard quick-action discovery.

## Requirements

### Requirement: Default state on first open

The system MUST open `CalculatorPage` with top pane `USD` and bottom pane `VES`, both showing `0`. The active pane MUST default to top. The default rate source MUST be `Paralelo`. No network call MUST block first paint.

#### Scenario: First launch with warm cache

- GIVEN `DolarApiService.instance` has cached `paraleloRate`
- WHEN the user navigates to Calculadora
- THEN top pane reads `USD`, bottom pane reads `VES`, source chip reads `Paralelo`
- AND both amount displays read `0`

#### Scenario: First launch offline with no cache

- GIVEN no rate has ever been fetched and the device is offline
- WHEN the user opens Calculadora
- THEN the source chip MUST default to `Manual`
- AND a non-blocking inline warning MUST appear (i18n key `calculator.warn.no_rate`)
- AND the page MUST render without throwing

### Requirement: Amount entry and arithmetic

The active pane MUST accept digits `0-9`, locale-aware decimal separator, backspace, `C`, `+`, and `−`. Arithmetic MUST evaluate via the existing `evaluate_expression.dart` engine. The non-active (converted) pane MUST update reactively after each keystroke. Operators `×` and `÷` MUST NOT appear on the keypad in v1.

#### Scenario: Locale-aware decimal separator

- GIVEN the device locale is `es-VE`
- WHEN the keypad renders
- THEN the decimal key MUST display `,`
- AND under `en-US` locale it MUST display `.`

#### Scenario: Sum before convert

- GIVEN top pane is `USD`, bottom is `VES`, source `Paralelo`, rate `100`
- WHEN the user types `100 + 50`
- THEN top pane displays `150` USD
- AND bottom pane displays `15.000,00` VES (locale-formatted)

### Requirement: Swap preserves entered amount

Tapping the round green swap button between panes MUST exchange the top and bottom currencies, mark the new top pane as active, and re-derive the converted value using the inverted rate. The numeric value the user typed MUST move with the pane it was entered into.

#### Scenario: Swap inverts conversion

- GIVEN top `USD = 100`, bottom `VES = 15.000`, source `Paralelo`
- WHEN the user taps swap
- THEN top reads `VES = 15.000`, bottom reads `USD = 100`
- AND further keystrokes target the new top pane

### Requirement: Source chip cycles BCV → Paralelo → Promedio → Manual

The source chip MUST cycle in that fixed order on tap. Switching sources MUST recompute the converted pane synchronously from cached rates without a network call. A "hace N min" timestamp MUST display next to the chip using the cached `lastFetched` value, localized.

#### Scenario: Cycle from Paralelo to Promedio

- GIVEN source is `Paralelo` with cached `BCV` and `Paralelo` rates
- WHEN the user taps the chip
- THEN source becomes `Promedio` computed as `(BCV + Paralelo) / 2`
- AND the converted pane updates without a network round-trip

#### Scenario: USDT label

- GIVEN top pane is set to `USDT`
- WHEN any source other than `Manual` is active
- THEN the chip MUST read `Paralelo (USDT)` regardless of cycle position

### Requirement: Manual rate is ephemeral by default

Selecting `Manual` MUST reveal an inline numeric field. The entered value MUST apply to all conversions in the current page session and MUST NOT write to the `exchangeRates` table. Closing or popping `CalculatorPage` MUST discard the manual value; reopening MUST default to `Paralelo`. An adjacent "Guardar como tasa manual" link MUST open the existing `ExchangeRateFormDialog` pre-filled with the entered value for explicit persistence.

#### Scenario: Manual value lives only in session

- GIVEN the user enters manual rate `490` and converts amounts
- WHEN the user pops Calculadora and reopens it
- THEN source chip MUST read `Paralelo`
- AND no `exchangeRates` row MUST have been written

#### Scenario: Persist via existing dialog

- GIVEN the user has entered manual rate `490`
- WHEN the user taps "Guardar como tasa manual"
- THEN `ExchangeRateFormDialog` MUST open with rate field pre-filled `490`

### Requirement: Refresh fetches and updates timestamp

A pull-to-refresh gesture AND an AppBar refresh icon MUST call `DolarApiService.instance.fetchAll()`. On success the timestamp label MUST update in place; on failure the previous values MUST remain and a non-blocking error toast MUST surface.

#### Scenario: Refresh on stale cache

- GIVEN the cached rate is older than 1 hour
- WHEN the user pulls to refresh
- THEN `fetchAll()` is invoked once
- AND the timestamp label updates without a full page rebuild

### Requirement: Share action with branded image and text fallback

The AppBar share action MUST render `ShareCard` via `RepaintBoundary.toImage(pixelRatio: 3)` (capped at `2` for screens with shortest side <360 dp), write a temp PNG, and invoke `Share.shareXFiles` with both the file AND a plain-text companion payload containing the same conversion. On render failure the system MUST fall back to `Share.share(plainText)` and MUST NOT surface an error toast.

#### Scenario: Happy path branded share

- GIVEN a valid conversion `$25.00 → Bs. 12.118,50` at `Paralelo`
- WHEN the user taps share
- THEN the OS share sheet opens with a PNG attachment AND a text payload
- AND the text payload contains amount, currencies, source label, and timestamp

#### Scenario: Render failure falls back to text

- GIVEN `RepaintBoundary.toImage` throws
- WHEN the share action runs
- THEN `Share.share(plainText)` MUST be called instead
- AND no error toast MUST appear

### Requirement: Quick action wiring is opt-in

`QuickActionId.goToCalculator` MUST be appended to the enum (never reordered) and registered in `kQuickActions` under `QuickActionCategory.navigation` with `Icons.calculate_outlined`. It MUST NOT appear in the default `quickUse` chip set; it MUST appear in `QuickUseConfigSheet` so users opt in. When enabled, tapping the chip MUST route to `CalculatorPage` via `RouteUtils.pushRoute`.

#### Scenario: Default chip set unchanged

- GIVEN a user upgrading from a previous build
- WHEN the dashboard loads
- THEN the persisted `quickUse` JSON MUST parse without migration
- AND `goToCalculator` MUST NOT appear in the rendered chip set

#### Scenario: Opt-in routes correctly

- GIVEN the user enables `goToCalculator` in `QuickUseConfigSheet`
- WHEN the chip is tapped
- THEN `CalculatorPage` MUST open via `RouteUtils.pushRoute`

### Requirement: Secondary entry points

Calculadora MUST be reachable from at least three entry points: the opt-in quick-action chip, a small "Calculadora" button in `CurrencyManagerPage`'s rates table, and a settings menu link. Behavior of `CurrencyManagerPage` outside this new button MUST NOT change.

#### Scenario: Currency manager button

- GIVEN the user is on `CurrencyManagerPage`
- WHEN the user taps the "Calculadora" button next to the rates table
- THEN `CalculatorPage` opens via `RouteUtils.pushRoute`

### Requirement: i18n in en and es only

New `calculator.*` keys MUST be added to `lib/i18n/json/en.json` and `lib/i18n/json/es.json` only. The 8 secondary locale files MUST NOT be touched; missing keys there MUST fall through to `en.json` per the slang base-locale convention.

#### Scenario: Secondary locale falls through

- GIVEN device locale is `pt`
- WHEN `CalculatorPage` renders
- THEN strings MUST resolve from `en.json` for any unlocalized `calculator.*` key
- AND no rendering exception MUST occur

### Requirement: Accessibility

Interactive controls MUST expose semantic labels: the swap button MUST have `Semantics.label = calculator.a11y.swap`, the source chip MUST have `Semantics.label` describing current source AND last-fetch age, and each keypad key MUST have a textual `Semantics.label`. The share-card image MUST always be paired with a textual share payload so screen readers and "Save text" share targets receive equivalent content.

#### Scenario: Screen reader on source chip

- GIVEN TalkBack is enabled and source is `Paralelo` updated 12 min ago
- WHEN focus lands on the chip
- THEN the announced label MUST include both source name and "hace 12 min"

### Requirement: No schema migration, no new dependencies

This change MUST NOT modify the Drift schema, MUST NOT bump `schemaVersion`, and MUST NOT add entries to `pubspec.yaml`. `flutter analyze` MUST remain clean after the change is applied.

#### Scenario: pubspec untouched

- GIVEN the change is fully applied
- WHEN `git diff pubspec.yaml` runs
- THEN the diff MUST be empty
