## Exploration: onboarding-v2-auto-import

### Current State

**Onboarding widget.** The current flow lives entirely in `lib/app/onboarding/onboarding.dart` (~1280 LOC, single file) as `OnboardingPage` — a `StatefulWidget` with a local `PageController` and `AnimatedSmoothIndicator` driving exactly 4 pages (line 126: `static const int _totalPages = 4`):

1. `_WelcomePage` (lines 356–467) — hero icon, Wallex tagline, 3 feature badges, 3 feature tiles. Pure content, no interaction.
2. `_PermissionsPage` (lines 472–609) — `WidgetsBindingObserver` that wires `PermissionCoordinator.check()` on `didChangeAppLifecycleState` and renders two `_PermissionTile`s (notifications + battery). Uses `requestNotificationListener()` + `requestPostNotifications()` + `openBatteryOptimizationSettings()` directly.
3. `_SetupPage` (lines 614–756) — 12-bank static grid (`_kBanks`, lines 32–105) with multi-select + USD/VES currency radio. All hardcoded Spanish strings, no slang.
4. `_ReadyPage` (lines 761–863) — check badge, "Incluido gratis" / "Con tu API key" feature lists.

**Handoff.** `_finish()` (lines 144–195) does, in order: `UserSettingService.setItem(SettingKey.preferredCurrency, ...)` → `PersonalVESeeder.seedAll(selectedBankIds: ...)` → `AppDataService.setItem(AppDataKey.introSeen, '1')` → `RouteUtils.pushRoute(PageSwitcher, withReplacement: true)`. No route-based handoff; it's an imperative `pushRoute`.

**First-run gate.** Two flags gate onboarding, both stored in the `appData` Drift table:
- `AppDataKey.onboarded` — set by auth (`welcome_screen.dart:80,154`, `login_page.dart`, `signup_page.dart`).
- `AppDataKey.introSeen` — set at the end of onboarding (`onboarding.dart:162`).

The gate is in `lib/main.dart` (lines 413, 464, 542, 558–586) inside `InitialPageRouteNavigator`:
```
if (!onboarded) → WelcomeScreen
else if (!introSeen) → OnboardingPage
else → PageSwitcher
```
Seed row in `lib/core/database/sql/initial/seed.dart:9` sets `introSeen = '0'`. `AppDataKey` enum has only 4 values (`app_data_service.dart:6`): `dbVersion, introSeen, lastExportDate, onboarded`.

**Slang i18n.** Config in `build.yaml:24-38`: base locale `en`, input `lib/i18n/json/`, output `lib/i18n/generated/translations.g.dart`, key_case `snake`, enum `AppLocale`. Ten locales (`de, en, es, fr, hu, it, tr, uk, zh-CN, zh-TW`). CLI: `dart run slang` (per `pubspec.yaml:111` comment).
**Relevant**: an `INTRO` namespace already exists in `es.json:169` with ~60 keys (`w_title`, `w_subtitle`, `perms_*`, `setup_*`, `ready_*`, plus legacy Monekin `sl1Title/sl2Title/lastSlideTitle`). **BUT `onboarding.dart` does NOT consume them** — grep for `t.INTRO|t.intro` in `lib/app/onboarding/` returns zero matches. Every string in the widget is a hardcoded Spanish literal. So the v3 rewrite must both (a) add new keys AND (b) actually wire `t.intro.*` for the first time.

**Auto-import services.** Under `lib/core/services/auto_import/`:
- `capture/device_quirks_service.dart` — singleton with `MethodChannel('com.wallex.capture/quirks')`. Exposes `detect()`, `isIgnoringBatteryOptimizations()`, `openBatteryOptimizationSettings()`, `openAutostartSettings()`, `openAppDetails()`. **Missing** a method to open `ACTION_NOTIFICATION_LISTENER_SETTINGS` — today the widget calls `PermissionCoordinator.requestNotificationListener()` which uses the `notification_listener_service` plugin's dialog (per the closed decision #5, this must be replaced with a direct MethodChannel firing `android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS`).
- `capture/permission_coordinator.dart` — `CapturePermissionsState` with `notificationListener`, `postNotifications`, `batteryOptimizationsIgnored`, `autostart/oemBatteryUserConfirmed`. Already has `requestNotificationListener`/`requestPostNotifications`. Good as-is; slide 7 can reuse it.
- `profiles/bank_profiles_registry.dart` — **static list**: `BdvSmsProfile, BdvNotifProfile, BinanceApiProfile` (Zinli is a TODO comment). There is NO runtime "detected bank apps → toggle" surface. Per-profile toggles are individual `SettingKey`s (`bdvSmsProfileEnabled`, `bdvNotifProfileEnabled`, `binanceApiProfileEnabled`, `zinliNotifProfileEnabled`) read via `UserSettingService.isProfileEnabled(profileId)`.

**UserSettings keys relevant to this change (exist today).** From `user_setting_service.dart:6-139`:
- ✅ `preferredCurrency` — slide 2 writes here.
- ✅ `preferredRateSource` — **already exists** (values `'bcv' | 'paralelo'`, default 'bcv'). Slide 3 just drives this existing setting. Not used by `onboarding.dart` today.
- ✅ Per-profile toggles listed above — slide 8 writes here.
- ✅ `autoImportEnabled`, `smsImportEnabled`, `notifListenerEnabled` — master toggles.
- ❌ No key for user goals/objetivos (slide 1).
- ❌ No concept of "detected installed bank packages" persisted anywhere.

**Manifest** (`android/app/src/main/AndroidManifest.xml`):
- ✅ Has `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `FOREGROUND_SERVICE` (+ `_SPECIAL_USE`), `WAKE_LOCK`, SMS perms.
- ✅ `NotificationListenerService` declared at line 84 (`notification.listener.service.NotificationListener` from the plugin) with `BIND_NOTIFICATION_LISTENER_SERVICE` permission.
- ✅ `<queries>` block exists (lines 121–140) with `PROCESS_TEXT`, battery-optimization intents, `RecognitionService`.
- ❌ `QUERY_ALL_PACKAGES` is **not** declared (closed decision #4 requires adding it + English TODO for Play Store flavor split).
- The comment at lines 62–71 confirms `:capture` isolate separation is in place.

**iOS.** There is no `ios/` directory (`ls ios` fails). Android + Windows are the only flutter_launcher_icons targets (`pubspec.yaml:118-124`). iOS branch of the flow (slides 5–8 collapse to Apple Shortcuts) has **no scaffolding to integrate with**. This is important: the closed decision #5 + iOS collapse is essentially aspirational today — the only concrete iOS work possible right now is conditional UI that shows a "coming soon / Apple Shortcuts" slide. No App Intents / Intents / Info.plist to touch.

**pubspec status.** Already present: `flutter_svg ^2.0.5`, `url_launcher ^6.3.1`, `slang ^4.9.1 + slang_flutter`, `permission_handler ^12.0.1`, `notification_listener_service ^0.3.5`, `device_info_plus ^11.3.0`, `shared_preferences`, `app_settings ^6.1.1`, `smooth_page_indicator ^1.2.1`, `dynamic_color ^1.7.0`. **Missing**: `google_fonts` (Gabarito + Inter), `flutter_animate` (for `v3-notif-in`/`v3-card-in`/`v3-pulse` stagger + pulse animations), and a package-listing library (see below).

**Orphaned SVGs.** `assets/icons/app_onboarding/` contains exactly: `first.svg`, `security.svg`, `upload.svg`, `wallet.svg`. Current `onboarding.dart` does not reference any of them (grep shows zero uses). They are Monekin-era holdovers. Decision: **purge all four** during the rewrite — v3 uses geometric placeholders + Material icons, no SVG illustrations.

**Reference uploads.** Directory `guia/uploads/` does **not exist** (ls failure). The checklist assumed it; it isn't there. Design source of truth is the v3 HTML + JSX files at the `guia/` root.

### Affected Areas

- `lib/app/onboarding/onboarding.dart` — full rewrite (delete 4-page widget, replace with 10-slide `PageView` wired to v3 tokens).
- `lib/app/onboarding/` (new siblings) — split the monolith: `onboarding_controller.dart` (state + finish), `slides/*.dart` (one per slide), `widgets/v3_phone.dart`, `widgets/v3_progress.dart`, `widgets/v3_notification_card.dart`, `theme/v3_tokens.dart`.
- `lib/main.dart:413, 464, 473, 558–586` — gate stays as-is (keep using `AppDataKey.introSeen`); no routing change needed.
- `lib/core/database/services/user-setting/user_setting_service.dart:6-139` — **add** `SettingKey.onboardingGoals` (JSON list of strings). `preferredRateSource` already exists.
- `lib/core/database/sql/initial/seed.dart:14-28` — seed default for new `onboardingGoals` key (empty JSON array or null).
- `lib/core/database/sql/migrations/` — new migration to insert the default row for `onboardingGoals` on existing installs.
- `lib/core/services/auto_import/capture/device_quirks_service.dart:52-266` — add `openNotificationListenerSettings()` that invokes a new MethodChannel op firing `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS`.
- `android/app/src/main/kotlin/.../MainActivity.kt` (or wherever `com.wallex.capture/quirks` is handled) — handle the new op.
- `android/app/src/main/AndroidManifest.xml:1-30` — add `<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>` with a `<!-- TODO: split Play Store flavor without QUERY_ALL_PACKAGES -->` English comment.
- `pubspec.yaml:22-98` — add `google_fonts`, `flutter_animate`, and a package-listing library (see Approaches).
- `pubspec.yaml:129-145` — remove `assets/icons/app_onboarding/` entry (all four SVGs deleted).
- `assets/icons/app_onboarding/*` — delete directory.
- `lib/i18n/json/*.json` (10 files) — replace the existing `INTRO` block with new snake_case keys under a new `intro_v3` namespace (or reuse `intro` cleaned up); regenerate via `dart run slang`.
- `lib/i18n/generated/translations.g.dart` — regenerated artifact.
- `lib/core/services/auto_import/profiles/bank_profiles_registry.dart:10-15` — no change needed; slide 8 reads the existing per-profile `SettingKey` toggles.
- `lib/core/database/utils/personal_ve_seeders.dart:23-43` — unchanged (called by slide-seeding step).

### Approaches

#### Fork A — Persistence for slide-1 "objetivos"

1. **New UserSettings key (recommended)** — `SettingKey.onboardingGoals` storing a JSON-encoded `List<String>` (e.g. `["track_expenses","save_usd","reduce_debt","budget","analyze"]`).
   - Pros: zero migration complexity beyond one INSERT, matches existing pattern (`fieldsToUseLastUsedValue`, `defaultTransactionValues` already store JSON this way per the docstrings in `user_setting_service.dart:47-50`). Writable/readable via existing `UserSettingService` APIs.
   - Cons: JSON-in-string is weak typing; if goals grow structure (e.g. per-goal weights) we'd refactor later.
   - Effort: Low.
2. **New Drift table `OnboardingGoals`** — rows per goal with `selected: bool`, `selectedAt: DateTime`.
   - Pros: queryable, extensible.
   - Cons: overkill — goals are read once by analytics/dashboard, never queried relationally; adds a schema migration + service + generated code noise for 5 static strings.
   - Effort: Medium.

#### Fork B — Installed-apps detection for slides 4 + 8

1. **`installed_apps` package** (recommended) — actively maintained, null-safe, simple API (`InstalledApps.getInstalledApps(true, true)` → list of `AppInfo`). Small footprint.
   - Pros: Maintained, matches use case.
   - Cons: Requires `QUERY_ALL_PACKAGES` on Android 11+ (already a closed decision). iOS returns empty list (fine — iOS collapses to Apple Shortcuts slide anyway).
2. **`device_apps` package** — similar API but last updated 2022; reported issues on Android 14+.
   - Pros: Cleaner API.
   - Cons: Stale maintenance.
3. **Kotlin-side enumeration via existing `com.wallex.capture/quirks` MethodChannel** — add `listInstalledPackages(filter)` op.
   - Pros: No new Dart dep; full control over filtering.
   - Cons: More native code to write + maintain; no real win given the Dart plugin works. **Only consider if `installed_apps` has an incompatibility on Android 15 POCO Rodin.**

#### Fork C — Notification Listener deep link

1. **New MethodChannel op on existing channel (recommended)** — add `openNotificationListenerSettings` to `com.wallex.capture/quirks` (both Dart side in `DeviceQuirksService` and Kotlin side), firing `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` with `FLAG_ACTIVITY_NEW_TASK`. Per closed decision #5, this replaces the `notification_listener_service` plugin's `requestPermission()` call (which shows an in-app dialog on some devices rather than opening the toggle screen).
   - Pros: Leverages existing channel + OEM quirks detection. Matches the pattern used by `openBatteryOptimization` / `openAutostart`.
   - Cons: None.
2. Keep `NotificationListenerService.requestPermission()` — rejected by closed decision #5.

#### Fork D — i18n key namespacing

1. **Clean-slate `intro` namespace (recommended)** — rename existing `INTRO` block → `intro` (snake_case, 10 locales) with entirely new keys for the 10-slide flow. Leave the Monekin-era keys (`sl1Title`, `lastSlideTitle`) out. Since the current widget doesn't consume `t.INTRO.*`, there are no dangling references to fix.
   - Pros: Clean; matches `key_case: snake` config.
   - Cons: Requires translation pass for all 10 locales — or ship with es+en only and `fallback_strategy: base_locale` (already enabled at `build.yaml:37`) handles the rest.
2. Keep `INTRO` all-caps — works but inconsistent with config.

### Recommendation

- **A1** new `SettingKey.onboardingGoals` JSON.
- **B1** `installed_apps` package.
- **C1** extend `com.wallex.capture/quirks` MethodChannel with `openNotificationListenerSettings`.
- **D1** rename/rewrite under `intro` snake_case namespace, es+en day-1, other 8 locales via `fallback_strategy: base_locale` until translated.

Keep the routing gate (`AppDataKey.introSeen`) untouched — the rewrite is internal to `OnboardingPage`. Finish semantics stay identical: set `preferredCurrency`, call `PersonalVESeeder.seedAll`, flip `introSeen`, `pushReplacement` to `PageSwitcher`. What changes is the slide count, the token system, the permission/listener UX, and the new writes (`preferredRateSource`, `onboardingGoals`, per-profile toggles for detected apps).

Seeding + Listo slides run **while** the finalization work happens (categories are already pre-seeded to ~50 per `personal_ve_seeders.dart:39`, so the seeding slide is largely theatrical — use it as a cover for the `seedAll` call which can take 200-500 ms on cold install).

### Risks

- **iOS branch is imaginary.** No `ios/` directory exists. Slides 5–8's "iOS collapse to Apple Shortcuts" has nothing to integrate with today. Mitigation: ship Android-only for slides 5–8; gate the Shortcuts slide behind `Platform.isIOS` and show a "coming soon" card until iOS is actually added as a flutter platform target.
- **`QUERY_ALL_PACKAGES` = Play Store policy risk.** Google requires a declaration for sensitive permissions. Adding it without a flavor split is OK for sideload / F-Droid / AGPL public builds but **will block a Play Store submission** unless a flavored build omits it. Closed decision #4 acknowledges this with an English TODO. Mitigation: add the TODO inline in manifest, keep a sticky issue for the eventual `playstore` flavor.
- **Dynamic `ACTION_NOTIFICATION_LISTENER_SETTINGS` + MIUI.** MIUI may still route to an in-app overlay rather than the system page on some firmware. Mitigation: the existing OEM quirks copy (`device_quirks_service.dart:169-259`) already covers MIUI fallback instructions; slide 7 should show them inline when `OemQuirk.miui|hyperos` detected.
- **Seeding race.** `PersonalVESeeder.seedAll` is idempotent (checks `existingAccounts.isNotEmpty` at line 28), so re-entry from the Seeding slide is safe — but if the user quits during seeding mid-INSERT, we could end up with partial categories. Mitigation: wrap the call in a transaction or rely on the existing guard (already safe because the guard runs first).
- **Slang regen discipline.** Forgetting `dart run slang` after editing JSON will produce a broken build. Mitigation: call it out in `tasks.md` and in the PR checklist.
- **`installed_apps` on Android 15 POCO Rodin** (user's daily driver per MEMORY). Package is maintained but I can't verify compat from static analysis. Mitigation: add smoke-test task and have a fallback to hardcoded `_kBanks` list if the detection throws.
- **Legacy `INTRO` i18n keys.** Removing them is safe because the current widget doesn't read them, **but** grep should be run across the codebase once more before deletion to confirm no other widget consumes `t.INTRO.w_title` etc. Mitigation: one final grep before delete.

### Ready for Proposal

**Yes.** All closed decisions are respected; the 4 genuine forks above have clear recommendations. The orchestrator should tell the user: "Exploration complete — current onboarding is a 4-page `StatefulWidget` with hardcoded Spanish strings and no slang wiring; `preferredRateSource` and per-bank profile toggles already exist so slides 3 and 8 can drive existing settings; iOS has no scaffolding so slides 5–8 will be Android-only with an iOS 'coming soon' placeholder; recommended stack adds `google_fonts`, `flutter_animate`, `installed_apps`, plus one new MethodChannel op, one new `SettingKey.onboardingGoals`, and `QUERY_ALL_PACKAGES` in manifest with TODO. Ready to run `/sdd-propose onboarding-v2-auto-import`."
