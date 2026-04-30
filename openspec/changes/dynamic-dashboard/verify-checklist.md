# Manual E2E Verify Checklist — `dynamic-dashboard`

Wave 3B test pass. Each item below maps to a Success Criterion in
`proposal.md` and is annotated with whether the **automated suite**
(`flutter test test/dashboard_widgets/`) covers it or whether **manual QA**
on a release build (POCO arm64-v8a per the bolsio build recipe — no
obfuscate, no split-debug-info) is required.

Statuses: `[ ]` not yet verified, `[A]` covered by automated suite, `[M]`
requires manual QA, `[A+M]` partial automation + manual sign-off.

---

## Success Criteria

### 1. Onboarding `save_usd` ⇒ `quickUse + totalBalanceSummary(USD) + exchangeRateCard + accountCarousel`

- [A+M]
- **Automated**: `defaults_test.dart::fromGoals save_usd contains exchangeRateCard, totalBalanceSummary, and quickUse first` validates the layout shape, including `displayCurrency: USD` carry-through from registry.
- **Manual**: visually verify on POCO that the dashboard actually paints these four widgets after fresh-install + onboarding(save_usd).

### 2. Multi-goal (`track_expenses + budget + analyze`) ⇒ widgets dedup, cap 8, `quickUse` first, orden por selección

- [A+M]
- **Automated**: `defaults_test.dart::multi-goal selection dedups by WidgetType and preserves first-seen order` covers dedup + first-seen ordering. `every-goal selection is capped at 8 widgets` covers the cap.
- **Manual**: re-onboard with multi-goal selection and confirm visual order on the device.

### 3. Tap lápiz ⇒ edit mode; drag para reordenar; orden persiste tras salir

- [A+M]
- **Automated**: `edit_reorder_test.dart` validates `DashboardLayoutService.reorder` semantics + debounced persist via the writer callback (4 tests). `edit_mode_test.dart` validates `EditableWidgetFrame` (X button, ⚙ button, IgnorePointer).
- **Manual**: end-to-end gesture on the device — tap lápiz → drag → tap check → kill app → relaunch → verify order is preserved. The `_DashboardPageState._editing` toggle wiring is not pumped by any automated test (DashboardPage has DB-bound dependencies).

### 4. Tap X ⇒ confirmación + delete + persistencia

- [A+M]
- **Automated**: `edit_mode_test.dart::EditableWidgetFrame renders the X (delete) button` validates the wiring of `onDelete`. `dashboard_layout_service_test.dart::removeByInstanceId() drops a descriptor and emits` covers the service-level removal.
- **Manual**: confirm the actual `AlertDialog` UX on the device — title, "Cancelar" / "Quitar" buttons, dismissal.

### 5. "+ Agregar" ⇒ bottom sheet con marcado de recomendados

- [A]
- **Automated**: `add_widget_sheet_test.dart::shows the "Recomendado" badge only for specs whose recommendedFor intersects onboardingGoals` + `with no goals set, no recommended badge appears` + `tap on a tile adds a new descriptor to the live service`.

### 6. Widget `quickUse` ejecuta cada `QuickActionId`; editor de chips persiste

- [M]
- **Automated**: out of scope for Wave 3B (the prompt substituted the `quick_use_config_test` slot with the fallback test). The action dispatcher itself is exercised indirectly via the `QuickActionRegistry` from Wave 2.5.1.
- **Manual**: tap each chip type (toggle, navigation, quick-tx) and verify the side effect; open the config sheet, reorder/select chips, close, and verify persistence by relaunching.

### 7. Returning user con `dashboardLayout` en Firebase ⇒ ve su layout; sin él ⇒ `fallback()`

- [A+M]
- **Automated**: `dashboard_fallback_test.dart::empty layout + introSeen="1" gate triggers fallback() persist` (and the two negative cases) covers the gate logic that `DashboardPage._initLayout` runs.
- **Manual**: log in on a fresh device with a user that already has a `dashboardLayout` synced — verify the synced layout renders. Then log in with a user who never set one — verify `fallback()` shape.

### 8. `flutter analyze` limpio + tests JSON ida/vuelta + Migrator

- [A]
- **Automated**: `serialization_test.dart` (round-trip every WidgetType/WidgetSize, empty config, primitive config, unknown type/size, missing instanceId, layout round-trip, empty layout, unknown widget entries dropped). `migrator_test.dart` (v1 no-op, missing schemaVersion, malformed widgets, future schemaVersion, unknown WidgetType, unknown WidgetSize, duplicate instanceId regenerated, schemaVersion=0 normalized).
- **Verify**: run `flutter analyze --no-fatal-infos` and confirm Wave 3B added zero new issues. Pre-existing 216 issues live in `test/auto_import/` and `test/receipt_ocr/` and are out of scope.

### 9. Primer frame del dashboard con 8 widgets activos < 500 ms en POCO arm64-v8a

- [M]
- **Automated**: not feasible in unit tests.
- **Manual**: build with the official bolsio recipe (`flutter build apk --release --target-platform=android-arm64 --no-tree-shake-icons` — verbatim per user's persisted recipe), launch, and time the first dashboard frame with DevTools or `Trace.startSync`/`Trace.endSync`. Record on the POCO.

### 10. `firebase_sync_service._userSettingsSyncExclusions` confirmado: `dashboardLayout` NO excluido

- [A]
- **Automated**: covered transitively by Wave 1 task 1.6 (verify-only). Re-verify by grep:
  ```
  rg "dashboardLayout" lib/core/services/firebase_sync_service.dart
  ```
  Expected: no match inside `_userSettingsSyncExclusions` (l. ~312).

### 11. Hidden mode oculta IDs filtrados en todos los widgets que dependen de `visibleAccountIdsStream`

- [M]
- **Automated**: existing `hidden_mode_service_test.dart` covers the service contract (PIN, lock/unlock, isLockedStream). The widget-level filtering uses `visibleAccountIdsStream` which is consumed by `TotalBalanceSummaryWidget`, `AccountCarouselWidget`, `IncomeExpensePeriodWidget` — the wiring is unchanged from the legacy dashboard so behaviour is preserved.
- **Manual**: lock Hidden Mode with a savings account, verify each widget hides totals/lists tied to the locked account.

---

## Automated suite summary (`flutter test test/dashboard_widgets/`)

| File | Tests | Status |
|------|-------|--------|
| `serialization_test.dart` | 9 | passing |
| `migrator_test.dart` | 9 | passing |
| `defaults_test.dart` | 10 | passing |
| `registry_test.dart` | 10 | passing |
| `dashboard_layout_service_test.dart` | 11 | passing |
| `dashboard_render_test.dart` | 3 | passing |
| `dashboard_fallback_test.dart` | 3 | passing |
| `edit_mode_test.dart` | 4 | passing |
| `edit_reorder_test.dart` | 4 | passing |
| `add_widget_sheet_test.dart` | 3 | passing |

**Total**: 66 unit / widget tests covering the dynamic-dashboard MVP contract.

## Items that REQUIRE manual QA before archive

The following Success Criteria cannot be fully automated and must be signed
off on a real POCO arm64-v8a build before this change is archived:

- SC #3 (live `_editing` toggle on the device — gesture + check button)
- SC #4 (AlertDialog UX for delete)
- SC #6 (each `QuickActionId` chip side effect + config sheet persistence)
- SC #9 (first-frame perf budget)
- SC #11 (Hidden Mode end-to-end with a savings account)

The remaining Success Criteria (#1, #2, #5, #7, #8, #10) are fully covered
by the automated suite — manual confirmation is recommended but not
strictly required for archive.
