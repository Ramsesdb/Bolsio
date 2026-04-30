# Proposal: Exchange Rate Widget Config

## Intent

Fix a display bug where the exchange rate card shows "EUR/EUR" instead of useful rates, and add a config editor so users can choose which currency pairs the widget displays. Also add a runtime-computed Promedio row (BCV + Paralelo average) to improve VES-centric users' daily workflow.

## Scope

### In Scope
- Bug fix: `_effectiveCurrencies()` seeds with `['VES', 'EUR']` (or `['USD', 'EUR']` when pref ≠ USD) — remove the broken preferredCurrency-removal logic
- Fix `defaults.dart`: `exchangeRateCard` defaultConfig respects `preferredCurrency` (USD→`['VES','EUR']`; VES→`['USD','EUR']`)
- New bottom sheet `exchange_rate_config_sheet.dart` (add/remove currencies, Wallex visual language)
- Promedio row: computed at runtime as `(BCV + Paralelo) / 2` when both sources present for a given pair
- Wire `configEditor` builder in `registry_bootstrap.dart` (same import-cycle pattern as quickUse)

### Out of Scope
- USDT support (deferred to future iteration)
- Auto-migration of existing user configs
- Changing `unique: false` (multiple instances remain allowed)

## Approach

Follow the QuickUse config sheet pattern:
1. Global `Widget Function(BuildContext, WidgetDescriptor)?` variable in widget file → set in `registry_bootstrap.dart`
2. Config sheet is a `StatefulWidget`; reads `descriptor.config` at `initState`, calls `DashboardLayoutService.instance.updateConfig(...)` on each change
3. Currency picker queries only currencies that have live rate rows (avoids dead entries)
4. Promedio row is pure UI logic — no DB write, computed in `build()` from existing rate stream data

No Drift schema migrations required — rates already stored, config already JSON.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/app/home/dashboard_widgets/widgets/exchange_rate_card_widget.dart` | Modified | Bug fix + Promedio row + configEditor variable |
| `lib/app/home/dashboard_widgets/edit/exchange_rate_config_sheet.dart` | New | Config bottom sheet |
| `lib/app/home/dashboard_widgets/registry_bootstrap.dart` | Modified | Wire configEditor builder |
| `lib/app/home/dashboard_widgets/defaults.dart` | Modified | Fix defaultConfig based on preferredCurrency |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Existing users see no change (stale config `['USD','EUR']` with USD removed) | High | Config sheet lets them manually fix; no auto-migration needed |
| Currency picker lists currencies with no rate data | Med | Filter picker to currencies present in rate DB rows |
| Import cycle (config sheet ↔ widget file) | Low | Global builder variable pattern already proven by quickUse |

## Rollback Plan

All changes are isolated to 4 files, no DB migration. Revert commits for those files; existing widget continues to render (even if with the EUR/EUR bug) without data loss.

## Dependencies

- `DashboardLayoutService.instance.updateConfig` — existing API, no changes needed
- `CurrencyService.getAllCurrencies()` — existing stream, used to filter picker list
- No new packages required

## Success Criteria

- [ ] Widget with default config shows VES/USD and VES/EUR rows (not EUR/EUR)
- [ ] `defaults.dart` produces correct seed currencies for both USD and VES preferredCurrency
- [ ] Config sheet opens from widget long-press/edit, add/remove currencies persists across hot restart
- [ ] Promedio row appears when both BCV and Paralelo rates are present; hidden otherwise
- [ ] No import cycle errors (`flutter analyze` clean)
- [ ] Multiple widget instances each retain independent configs
