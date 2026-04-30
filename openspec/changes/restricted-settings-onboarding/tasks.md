# Tasks: Restricted Settings Onboarding Step

Atomic, dependency-ordered checklist organized into 5 tandas (single-session batches). Each tanda has a verification gate. Per project memory, `flutter test` is NOT run inside tandas — only `flutter analyze`. Widget tests are deferred to a post-merge follow-up.

---

## Tanda 1: Native + service plumbing (foundation, no UI)

Depends on: nothing. Critical path entry.

- [x] 1.1 In `android/app/src/main/kotlin/com/bolsio/app/DeviceQuirksChannel.kt`, add private fun `isRestrictedSettingsAllowed(context: Context): Boolean` per design § Implementation sketch — `Build.VERSION.SDK_INT < Build.VERSION_CODES.S` returns `true`; uses `AppOpsManager.unsafeCheckOpNoThrow("android:access_restricted_settings", Process.myUid(), packageName)`; returns `true` for `MODE_ALLOWED` or `MODE_DEFAULT`; `try/catch` fail-open returning `true` on any exception.
- [x] 1.2 In the same file, add the channel branch `"isRestrictedSettingsAllowed" -> result.success(isRestrictedSettingsAllowed(context))` inside the existing `setMethodCallHandler` switch.
- [x] 1.3 In `lib/core/services/auto_import/capture/device_quirks_service.dart`, add `Future<bool> isRestrictedSettingsAllowed()` wrapper: returns `true` when `!Platform.isAndroid`; invokes `_channel.invokeMethod<bool>('isRestrictedSettingsAllowed')`; `try/catch` returns `true` on `PlatformException` or any error (fail-open).
- [x] 1.4 In `lib/core/services/auto_import/capture/permission_coordinator.dart`, add `final bool restrictedSettingsAllowed;` to `CapturePermissionsState`; default `true` in `.initial()`; update `copyWith`, `==`, and `hashCode` to include the new field.
- [ ] 1.5 In `PermissionCoordinator.check()`, populate `restrictedSettingsAllowed` by awaiting `DeviceQuirksService.instance.isRestrictedSettingsAllowed()` and threading it into the returned state. *(Deferred to host integration tandas per orchestrator scope — data-class change only in Tanda 1.)*

**Verification gate**: `flutter analyze` clean + visual review of diff (Kotlin compiles, Dart wrapper signature matches, state field round-trips through `copyWith`).

---

## Tanda 2: Shared widget + i18n

Depends on: Tanda 1 verified.

- [x] 2.1 Create `lib/app/onboarding/widgets/v3_restricted_settings_step.dart` per design § Shared widget API — props: `onContinue`, `onOpenAppInfo`, `showBackPill = true`. Internal state: `_awaitingResume: bool`, `_stillBlocked: bool`.
- [x] 2.2 In the same widget, implement `WidgetsBindingObserver`: on `AppLifecycleState.resumed && _awaitingResume`, call `DeviceQuirksService.instance.isRestrictedSettingsAllowed()` → if `true` invoke `widget.onContinue()`; else `setState(_stillBlocked = true)`. Set `_awaitingResume = true` when primary CTA tapped (via `onOpenAppInfo`).
- [x] 2.3 Render UI: `V3SlideTemplate` (gated by `showBackPill`) + `V3MiniPhoneFrame` stylized App Info mockup with kebab `⋮` highlighted; title/subtitle; 3 numbered inline steps (text-only); primary filled CTA `t.onboarding.restrictedSettings.ctaPrimary`; secondary text CTA `t.onboarding.restrictedSettings.ctaSkip`; `_stillBlocked` hint as 1-line italic body-small in `colorScheme.onSurfaceVariant`.
- [x] 2.4 Add 9 keys to `lib/i18n/json/en.json` under `onboarding.restricted_settings.*`: `title`, `subtitle`, `step1`, `step2`, `step3`, `cta_primary`, `cta_skip`, `still_blocked_hint`, `success_toast` (per design § i18n Keys table, EN column).
- [x] 2.5 Add the same 9 keys to `lib/i18n/json/es.json` (canonical Spanish, ES column). Do NOT duplicate into the other 9 locales — Slang `fallback_strategy: base_locale` handles them.
- [x] 2.6 Run `dart run slang` to regenerate `lib/i18n/generated/translations*.g.dart`.

**Verification gate**: `flutter analyze` clean + visual review of diff (no orphan keys reported by slang; widget compiles; lifecycle observer registered/unregistered in `initState`/`dispose`).

---

## Tanda 3: Host integration — `OnboardingPage`

Depends on: Tanda 2 verified. Can run in parallel with Tanda 4 if two engineers split (no shared files).

- [x] 3.1 Create `lib/app/onboarding/slides/s075_restricted_settings.dart` as a thin adapter (`Slide075RestrictedSettings`) that wraps `V3RestrictedSettingsStep` with `showBackPill: true` and forwards `onNext` to both `onContinue` and `onOpenAppInfo` callbacks via `DeviceQuirksService.instance.openAppDetails()`.
- [x] 3.2 In `lib/app/onboarding/onboarding.dart` `_OnboardingPageState`, add fields `bool _restrictedSettingsBlocked = false;` and (if not present) `bool _isAndroid`.
- [x] 3.3 In `_OnboardingPageState.initState`, call private `_resolveRestrictedSettings()` async helper that — when `_isAndroid == true` — awaits `DeviceQuirksService.instance.isRestrictedSettingsAllowed()` and `setState(() => _restrictedSettingsBlocked = true)` only when the call returns `false` (and widget is still `mounted`).
- [x] 3.4 In `_buildSlides()`, conditionally insert `Slide075RestrictedSettings` between s07 (`s07_post_notifications`) and s08 (`s08_activate_listener`) when `_isAndroid && _restrictedSettingsBlocked`. Length and order MUST be invariant when the flag is `false`.

**Verification gate**: `flutter analyze` clean + visual review of diff (slide list length parametric; progress bar reflects new length; no regression in the non-Android / non-blocked path).

---

## Tanda 4: Host integration — `ReturningUserFlow`

Depends on: Tanda 2 verified. Independent of Tanda 3 (parallelizable).

- [x] 4.1 In `lib/app/auth/returning_user_flow.dart` `_ReturningUserFlowState`, add fields `bool _restrictedSettingsBlocked = false;` and `bool _restrictedSettingsResolved = false;` (and `_isAndroid` if not present).
- [x] 4.2 In `initState`, call `_resolveRestrictedSettings()` helper: on non-Android set `_restrictedSettingsResolved = true` immediately; on Android, await `DeviceQuirksService.instance.isRestrictedSettingsAllowed()` and `setState` both `_restrictedSettingsBlocked = !allowed` and `_restrictedSettingsResolved = true` when `mounted`.
- [x] 4.3 Expand `_step` machine from `0|1` to `0|1|2`: 0 = welcome-back hero, 1 = `V3RestrictedSettingsStep` (when blocked), 2 = `_ActivateListenerStep`. In `_advanceFromWelcome()`, branch on `_restrictedSettingsBlocked` → `setState(_step = 1)` if true, else `setState(_step = 2)`.
- [x] 4.4 Render `V3RestrictedSettingsStep` at `_step == 1` with `showBackPill: false`; `onContinue` advances to `_step = 2`; `onOpenAppInfo` calls `DeviceQuirksService.instance.openAppDetails()`.
- [x] 4.5 Welcome-back primary CTA: while `!_restrictedSettingsResolved`, render an inline spinner inside the CTA (button stays disabled or shows loading state); enable normal advance when resolved.

**Verification gate**: `flutter analyze` clean + visual review of diff (state machine matrix verified for all 4 combinations: Android/non-Android × blocked/not-blocked).

---

## Tanda 5: Manual smoke test on POCO rodin

Depends on: Tandas 3 AND 4 verified. Environment setup required.

- [ ] 5.1 Environment: ensure ADB connection to POCO rodin via USB; confirm "Instalar vía USB" toggle is ON in MIUI dev options (per project memory `feedback_miui_adb_install`).
- [ ] 5.2 Build APK: `flutter build apk --release --split-per-abi --target-platform android-arm64`.
- [ ] 5.3 Push to device: `adb push build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /sdcard/Download/bolsio-restricted-settings.apk` (use `adb push` + manual install due to MIUI USER_RESTRICTED block on `adb install`).
- [ ] 5.4 Install manually via Files app on device; clear any prior Bolsio install state if needed (`adb shell pm clear com.bolsio.app`).
- [ ] 5.5 Verify positive path in `OnboardingPage`: gate active by default on sideload → traverse onboarding to s07 → s075 renders between s07 and s08 → tap primary CTA → App Info opens for `com.bolsio.app` → toggle "Allow restricted settings" ON → press back → app resumes → auto-advances to s08.
- [ ] 5.6 Verify "still blocked" path: at s075, tap primary CTA, return without toggling → inline 1-line hint renders; CTA still functional for retry.
- [ ] 5.7 Verify skip path: at s075, tap secondary "Hacer esto más tarde" → host advances to s08 with no persisted gate state; `SettingKey.notifListenerEnabled` unchanged.
- [ ] 5.8 Verify negative path (Play Store simulation): `adb shell appops set com.bolsio.app ACCESS_RESTRICTED_SETTINGS allow` → relaunch onboarding (clear app data first) → s075 does NOT appear; slide list length matches v2 baseline.
- [ ] 5.9 Verify `ReturningUserFlow` path: clear app data, sign in with Google account that has Firebase/Drift data restored → welcome-back hero renders → tap "Continuar" → restricted-settings step renders (no back-pill) → tap primary CTA → App Info opens → toggle on → return → auto-advances to `_ActivateListenerStep`.
- [ ] 5.10 Verify `ReturningUserFlow` negative: with AppOp set to `allow`, sign in with returning Google account → welcome-back → "Continuar" → goes directly to `_ActivateListenerStep` (no intermediate step).

**Verification gate**: All 10 manual checks pass on POCO rodin (HyperOS arm64-v8a). Capture screenshots for the verify-report.

---

## Critical path

Tanda 1 → Tanda 2 → (Tanda 3 ∥ Tanda 4) → Tanda 5

## Parallelization opportunities

Tandas 3 and 4 touch disjoint files (`onboarding.dart` + new slide vs `returning_user_flow.dart`) and can be implemented concurrently once Tanda 2 lands. All other tandas are strictly sequential.

## Out of scope (deferred)

- Widget tests for `V3RestrictedSettingsStep` (lifecycle stub harness) — post-merge follow-up.
- `Settings → Auto-import` row consuming `restrictedSettingsAllowed` — separate change.
- `success_toast` i18n key wiring — reserved for v2 UX.
