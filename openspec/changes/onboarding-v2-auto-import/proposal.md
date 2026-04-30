# Proposal: Onboarding v2 — Auto-Import First

## Intent

Replace the current 4-slide onboarding (`lib/app/onboarding/onboarding.dart`, ~1280 LOC, hardcoded Spanish, zero slang wiring) with a new 8 interactive + 2 closing slide flow that makes auto-import via `NotificationListenerService` the centerpiece. The v3 design (bundle at `guia/Bolsio Onboarding Flow v3.html` + `wo-v3-*.jsx` + `bolsio-theme.jsx`) reframes permissions as a guided sell (notif animation → privacy bullets → listener toggle deep link → detected apps). Because the repo has **no `ios/` directory** (iOS does not compile today as a Flutter target), slides 5–8 are gated by a **positive `Platform.isAndroid` check** — every non-Android runtime (web, desktop, and any future iOS target until it is properly scaffolded) skips straight to seeding + Listo. The positive check is intentional: a `!Platform.isIOS` formulation would silently mask the absence of the iOS target. Seeding is theatrical cover (~50 categories are already pre-seeded; `PersonalVESeeder.seedAll` is idempotent per `personal_ve_seeders.dart:28`) while user selections are applied in the background.

## Scope

### In Scope
- Full rewrite of `lib/app/onboarding/onboarding.dart` into a controller + per-slide files under `lib/app/onboarding/slides/` and reusable atoms under `lib/app/onboarding/widgets/` (progress bar, slide template, goal chip, currency tile, rate tile, bank tile, mini-phone, pulse row, notification card, seeding overlay).
- 10 slides total: Objetivos (multi-select), Moneda (USD/VES/DUAL), Tasa (BCV/Paralelo), Cuentas iniciales, Auto-import sell, Privacidad, Activar listener, Apps incluidas, Seeding overlay, Listo.
- Design tokens in `lib/app/onboarding/theme/v3_tokens.dart` using dynamic system light/dark with Material You accent fallback `#C8B560`; spacing {8,10,12,14,16,22,24,26}; radii {pill 999, lg 22, md 14, sm 10}; progress bar 3px segmented at top-52.
- Animations `v3-notif-in` (0.6s staggered), `v3-card-in` (opacity+scale 0.98→1), `v3-pulse` (2.4s halo rgba(200,181,96,0.15)) via `flutter_animate`.
- Slang namespace rewrite: purge legacy `INTRO` uppercase block in `lib/i18n/json/*.json` (10 locales), introduce `intro` snake_case keys. **Ship `es` + `en` complete day-1**; the other 8 locales (`de, fr, hu, it, tr, uk, zh-CN, zh-TW`) fall back to English via `fallback_strategy: base_locale` already set in `build.yaml:37`. Rationale: the onboarding's primary audience is Spanish-speaking Venezuelan users (BCV/Paralelo, Banco de Venezuela, Zinli themes); the current widget already ships hardcoded Spanish, so day-1 `es` coverage is not a regression. Community translations for the remaining 8 locales can land in subsequent PRs without blocking delivery.
- New `SettingKey.onboardingGoals` in `lib/core/database/services/user-setting/user_setting_service.dart` storing a JSON-encoded `List<String>` (no new table). Add the key to `lib/core/database/sql/initial/seed.dart` with default value `'[]'` for fresh installs. **No SQL migration required for existing installs**: `KeyValueService.setItem` uses `InsertMode.insertOrReplace` and `initializeGlobalStateMap` returns `null` for absent keys, so the reader treats `null` as empty list — same contract used by `firebaseSyncEnabled`, `defaultTransactionValues`, and the `*Enabled` auto-import toggles.
- New `BankDetectionService` at `lib/core/services/bank_detection/bank_detection_service.dart` wrapping the `installed_apps` package so UI never imports the lib directly; returns `const []` on non-Android.
- New `openNotificationListenerSettings()` op on `DeviceQuirksService` (`lib/core/services/auto_import/capture/device_quirks_service.dart`) reusing the existing `com.bolsio.capture/quirks` MethodChannel; Kotlin side fires `Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)` with `FLAG_ACTIVITY_NEW_TASK`.
- `android/app/src/main/AndroidManifest.xml`: add `QUERY_ALL_PACKAGES` with inline English `<!-- TODO: split Play Store flavor (foss vs play) to omit QUERY_ALL_PACKAGES -->`.
- `pubspec.yaml`: add `google_fonts` (Gabarito display + Inter UI), `flutter_animate`, `installed_apps`. Remove `assets/icons/app_onboarding/` entry.
- Delete orphaned SVGs: `assets/icons/app_onboarding/{first,security,upload,wallet}.svg`.
- Bank logos rendered as geometric placeholders using existing `_kBanks` brand colors; English TODO marker for real SVG swap later.

### Out of Scope
- iOS Shortcuts implementation (deferred — `ios/` directory absent).
- Play Store flavor split (`foss` vs `play`) — only an inline TODO is added.
- Real bank SVG logos (Ramses delivers separately).
- Onboarding analytics instrumentation.
- Paywall / BYOK / AI chat onboarding (Hero + Plan slides from designer's v3 dropped).
- "Categorias" slide — rejected; 50 are pre-seeded with CRUD at `lib/app/categories/form/category_form.dart`.

## Affected Modules

| Path | Impact |
|------|--------|
| `lib/app/onboarding/onboarding.dart` | Replace wholesale |
| `lib/app/onboarding/onboarding_controller.dart` | New |
| `lib/app/onboarding/slides/*.dart` | New (one file per slide) |
| `lib/app/onboarding/widgets/*.dart` | New reusable atoms |
| `lib/app/onboarding/theme/v3_tokens.dart` | New |
| `lib/i18n/json/*.json` (10 files) | Purge `INTRO`, add `intro` snake_case |
| `lib/i18n/generated/translations.g.dart` | Regenerated by `dart run slang` |
| `lib/core/database/services/user-setting/user_setting_service.dart` | Add `SettingKey.onboardingGoals` |
| `lib/core/database/sql/initial/seed.dart` | Add `onboardingGoals` row with `'[]'` default for fresh installs |
| `lib/core/services/bank_detection/bank_detection_service.dart` | New |
| `lib/core/services/auto_import/capture/device_quirks_service.dart` | Add `openNotificationListenerSettings()` |
| `android/app/src/main/kotlin/.../MainActivity.kt` (quirks handler) | Handle new op |
| `android/app/src/main/AndroidManifest.xml` | Add `QUERY_ALL_PACKAGES` + TODO |
| `pubspec.yaml` | Add 3 packages; remove `app_onboarding` asset entry |
| `assets/icons/app_onboarding/*.svg` | Delete |
| `lib/main.dart` | Untouched — gate stays on `AppDataKey.introSeen` |

## Drift Schema Migrations

**No migration of any kind required.** `SettingKey.onboardingGoals` reuses the existing key-value `userSettings` table. The migration runner (`app_db.dart:68-95`, `assets/sql/migrations/v$i.sql`) is not invoked because `schemaVersion` (`app_db.dart:98`) does **not** increment.

Rationale, verified against the existing service contracts:

- `KeyValueService.setItem` (`key_value_service.dart:34-64`) uses `InsertMode.insertOrReplace`; the row is created on first write without prerequisite.
- `KeyValueService.initializeGlobalStateMap` (`key_value_service.dart:26-32`) loads only the rows that exist; absent keys yield `null` from `appStateSettings`.
- The repository already documents and uses the contract «`null` = default» for sibling keys: `firebaseSyncEnabled`, `defaultTransactionValues`, `fieldsToUseLastUsedValue`, and every `*Enabled` auto-import/AI toggle in `user_setting_service.dart:60-138`.

Therefore the reader for `onboardingGoals` MUST interpret `null` as empty list, and the seed entry in `seed.dart` is added for documentary symmetry — not as a correctness requirement. The spec phase MUST NOT introduce a `vN.sql` migration for this change.

## Rollback Plan

Single-commit revert. Steps: `git revert <merge>` → `dart run slang` to regenerate the old `INTRO` keys (they reappear in JSON via the revert) → `flutter pub get` to drop the 3 new packages → rebuild. Because no `schemaVersion` bump and no `vN.sql` migration are introduced, the database requires no downgrade. Any `onboardingGoals` rows written into `userSettings` by the new flow remain in the table after revert; they are ignored by the reverted codepath and incur zero behavioural impact.

## Open Questions

None — all forks resolved during exploration (goals→`SettingKey.onboardingGoals` JSON; detection→`installed_apps` via `BankDetectionService`; listener deep link→`openNotificationListenerSettings` on existing MethodChannel; slang→`intro` snake_case purge).

## Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | iOS branch is imaginary — no `ios/` directory to integrate with. | Slides 5–8 gated by **positive `Platform.isAndroid` check** (not `!Platform.isIOS`, which would mask the absence of the iOS target). All non-Android runtimes (web, desktop, hypothetical future iOS) jump to seeding. Documented as deferred. |
| 2 | `QUERY_ALL_PACKAGES` blocks Play Store submissions unless flavored. | Inline English TODO in manifest referencing future `foss` vs `play` flavor split. Safe for sideload / F-Droid / AGPL public builds. |
| 3 | MIUI / HyperOS may intercept `ACTION_NOTIFICATION_LISTENER_SETTINGS` with overlay instead of system page. | Reuse existing OEM quirk copy in `device_quirks_service.dart:169-259`; if intent launch throws, fall back to `openAppDetails()` + toast instruction. |
| 4 | Seed race if user quits during seeding mid-INSERT. | Rely on existing idempotency guard at `personal_ve_seeders.dart:28` (`existingAccounts.isNotEmpty` check). Re-entry is safe. |
| 5 | Slang regen discipline — forgetting `dart run slang` after JSON edits breaks the build. | Mandatory step in `tasks.md` + PR checklist note. |
| 6 | `installed_apps` on Android 15 POCO Rodin unverified. | Smoke test on device; `BankDetectionService` falls back to the existing static `_kBanks` list if detection throws or returns empty. |
| 7 | Orphaned legacy SVGs at `assets/icons/app_onboarding/`. | Purge (delete files + pubspec asset entry) as part of this change. Grep confirmed zero references. |

## Success Criteria

- [ ] 10-slide flow renders with v3 tokens in light + dark system modes on POCO Rodin (Android 15).
- [ ] `AppDataKey.introSeen` flips on Listo CTA; `PageSwitcher` loads without restart.
- [ ] `SettingKey.onboardingGoals`, `preferredCurrency`, `preferredRateSource`, and any per-profile toggles selected in slide 8 are persisted and readable.
- [ ] Listener settings deep link lands on the system toggle screen (or documented MIUI fallback).
- [ ] `flutter analyze` clean; slang regen produces no missing keys for es + en.
- [ ] Legacy `INTRO` keys and `assets/icons/app_onboarding/` SVGs are gone; no dangling references.
