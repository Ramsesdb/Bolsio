# Spec: exchange-rate-widget-config

## Domain: dashboard-widgets / exchange-rate-card

---

## Requirements

### REQ-1: Effective Currencies Bug Fix

The widget MUST seed its currency list as `['VES', 'EUR']` by default and MUST NOT remove the preferred currency from that seed list.

#### Scenario: Default widget shows VES and EUR rows (not EUR/EUR)

- GIVEN a fresh install with preferredCurrency = USD
- WHEN the exchange rate card widget renders
- THEN it displays rows for VES and EUR
- AND no row reads "EUR/EUR"

#### Scenario: Widget with stale USD-removed config still renders

- GIVEN an existing user whose stored config contains `['EUR']` only
- WHEN the exchange rate card widget renders
- THEN it displays at least the EUR row without crashing
- AND no EUR/EUR deduplication occurs

---

### REQ-2: Default Config Respects Preferred Currency

`defaults.dart` MUST generate `exchangeRateCard.defaultConfig` based on `preferredCurrency`:

| preferredCurrency | currencies seed |
|---|---|
| USD | `['VES', 'EUR']` |
| VES | `['USD', 'EUR']` |
| other | `['USD', 'EUR']` |

#### Scenario: New install with USD preference gets VES+EUR defaults

- GIVEN a new install where preferredCurrency = USD
- WHEN dashboard defaults are built
- THEN exchangeRateCard defaultConfig.currencies = `['VES', 'EUR']`

#### Scenario: New install with VES preference gets USD+EUR defaults

- GIVEN a new install where preferredCurrency = VES
- WHEN dashboard defaults are built
- THEN exchangeRateCard defaultConfig.currencies = `['USD', 'EUR']`

#### Scenario: New install with non-USD/VES preference falls back to USD+EUR

- GIVEN a new install where preferredCurrency = EUR
- WHEN dashboard defaults are built
- THEN exchangeRateCard defaultConfig.currencies = `['USD', 'EUR']`

---

### REQ-3: Promedio Row

After all rate rows are built, the widget MUST append a computed "Promedio" row when both a `bcv` and a `paralelo` source row exist for the same base/quote pair. The row MUST be hidden when only one source is present. This MUST be pure UI computation — no DB write.

#### Scenario: Promedio row appears when BCV and Paralelo both present

- GIVEN the rate stream contains both a BCV row and a Paralelo row for VES
- WHEN the widget builds its rate list
- THEN a "Promedio" row appears after the VES rows
- AND its displayed value = `(bcv.rate + paralelo.rate) / 2`

#### Scenario: Promedio row hidden when only BCV is present

- GIVEN the rate stream contains a BCV row for VES but no Paralelo row
- WHEN the widget builds its rate list
- THEN no "Promedio" row is shown

#### Scenario: Promedio row hidden when only Paralelo is present

- GIVEN the rate stream contains a Paralelo row for VES but no BCV row
- WHEN the widget builds its rate list
- THEN no "Promedio" row is shown

---

### REQ-4: Config Bottom Sheet — Currency Management

The system MUST provide a config bottom sheet (`ExchangeRateConfigSheet`) where users can add or remove currencies displayed by the widget.

#### Scenario: Add a currency via config sheet

- GIVEN the config sheet is open and the widget currently shows `['VES', 'EUR']`
- WHEN the user taps a currency in the "Agregar divisa" section
- THEN that currency is appended to the widget's config
- AND the widget immediately reflects the new currency row

#### Scenario: Remove a currency via config sheet

- GIVEN the config sheet is open and the widget currently shows `['VES', 'EUR', 'USD']`
- WHEN the user taps the remove button next to EUR
- THEN EUR is removed from the widget's config
- AND the widget no longer shows an EUR row

#### Scenario: Config persists across hot restart

- GIVEN the user added GBP via the config sheet
- WHEN the app is fully restarted
- THEN the widget still shows a GBP row

---

### REQ-5: Currency Catalog Filters to Active Rates

The currency picker in the config sheet MUST only list currencies that have at least one existing rate row in the database.

#### Scenario: Currency with no rate rows is excluded from picker

- GIVEN the DB has rate rows for USD and VES but not for JPY
- WHEN the config sheet's "Agregar divisa" section loads
- THEN JPY does not appear in the picker list

#### Scenario: Currency with a rate row appears in picker

- GIVEN the DB has a rate row for EUR
- WHEN the config sheet's "Agregar divisa" section loads
- THEN EUR appears in the picker list

---

### REQ-6: Independent Config per Widget Instance

Each widget instance MUST store and apply its own config independently. Changing one instance's currencies MUST NOT affect another instance.

#### Scenario: Two instances retain independent currency lists

- GIVEN two exchange rate card instances on the dashboard
- AND instance A shows `['VES', 'EUR']` and instance B shows `['USD', 'EUR']`
- WHEN the user opens instance A's config sheet and removes EUR
- THEN instance A shows only `['VES']`
- AND instance B still shows `['USD', 'EUR']` unchanged
