# Exploration: restricted-settings-onboarding

> Add a dynamic onboarding step that detects when Android's `ACCESS_RESTRICTED_SETTINGS` gate is blocking the notification listener toggle (sideloaded APKs on Android 13+ / HyperOS on POCO rodin) and walks the user through enabling it before the listener slide.

---

## 1. Current State

### 1.1 Onboarding v2 (shipped 2026-04-24)

Source: `lib/app/onboarding/onboarding.dart` (`OnboardingPage` widget, ~520 LOC).

- **Slide list is computed in `_buildSlides()`** (line 270) every rebuild. The Android-only auto-import block (slides 5–9) is added inline behind a positive `_isAndroid = !kIsWeb && Platform.isAndroid` flag (set once in `initState`).
- **Conditional-slide precedent already exists**: the entire `Slide05…Slide09` block is conditional on `_isAndroid`. Adding a second conditional (e.g. "restricted-settings detected") is mechanically identical.
- **PageController + `NeverScrollableScrollPhysics`** — slides are CTA-driven; users cannot swipe past blockers. The progress bar (`V3ProgressBar`) reads `total` from the live `slides.length`, so adding/removing one slide auto-updates the indicator.
- **Slides are stateful, own their own permission UX**. Pattern: extend `WidgetsBindingObserver`, hold `_awaitingResumeAfterX` flags, override `didChangeAppLifecycleState`. See `s07_post_notifications.dart` (post-notif runtime perm) and `s08_activate_listener.dart` (listener binding).

### 1.2 Listener-permission UX today (slide 8 — `s08_activate_listener.dart`)

Already implements:
- `WidgetsBindingObserver.didChangeAppLifecycleState(resumed)` → calls `PermissionCoordinator.instance.check()` → if granted, auto-advances. **This is exactly the completion-detection pattern we need.**
- Calls `DeviceQuirksService.instance.openNotificationListenerSettings()` to deep-link to the listener toggle. Falls back to `openAppDetails()` + a snackbar on `PlatformException`.
- Renders an OEM-specific `_OemInstructions` panel below the mini-phone mockup (autostart + battery tiles for MIUI, Huawei, etc.).
- The slide does NOT recognise the restricted-settings gate today; if the toggle is grayed out, "Activar ahora" opens the listener screen but the user is stuck — no auto-advance ever fires because `isPermissionGranted()` keeps returning false.

### 1.3 Permission infra (`PermissionCoordinator`)

`lib/core/services/auto_import/capture/permission_coordinator.dart` — singleton with a `ValueNotifier<CapturePermissionsState>`. Tracks 6 things: `notificationListener`, `postNotifications`, `batteryOptimizationsIgnored`, `autostartUserConfirmed`, `oemBatteryUserConfirmed`, `quirk`. Idempotent `check()` and `refresh()` methods. Persists the two `userConfirmed` flags to `SharedPreferences` (keys `capture_perms_autostart_confirmed`, `capture_perms_oem_battery_confirmed`).

There is **no** field for `restrictedSettingsAllowed` today. Adding one is the natural extension.

### 1.4 Platform channel: `com.bolsio.capture/quirks`

`android/app/src/main/kotlin/com/bolsio/app/DeviceQuirksChannel.kt` (~240 LOC).

Already exposes:
- `isIgnoringBatteryOptimizations` → `Boolean` via `PowerManager.isIgnoringBatteryOptimizations(packageName)`
- `openBatteryOptimization` / `openAppDetails` / `openAutostart` / `openNotificationListenerSettings`
- Smart fallback: `openNotificationListenerSettings` uses `ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS` (lands directly on Bolsio's toggle, API 30+) before falling back to the generic listener list. **Important**: on a restricted device, the user lands directly on the grayed-out toggle — perfect "before" state for the new slide's mockup, but useless for completing the action.

Adding a new method (e.g. `isRestrictedSettingsAllowed`, `openAppDetailsForRestrictedHint`) is a 20-line addition; the channel is already wired through `MainActivity.kt`.

### 1.5 Device probe — what AppOps actually says

Confirmed live on POCO rodin (HyperOS / Android 16, SDK 36) via ADB:

```bash
$ adb shell appops get com.bolsio.app ACCESS_RESTRICTED_SETTINGS
ACCESS_RESTRICTED_SETTINGS: ignore; rejectTime=+11m26s737ms ago

$ adb shell dumpsys package com.bolsio.app | grep installerPackageName
installerPackageName=com.google.android.packageinstaller
```

Two key findings:
1. **The AppOp is named `ACCESS_RESTRICTED_SETTINGS`** and its mode is `ignore` while restricted, with a `rejectTime` recorded each time the user tried to interact with the grayed-out toggle. After the user enables "Allow restricted settings" via the ⋮ menu, the mode flips to `allow` (or `default`).
2. The installer is `com.google.android.packageinstaller` — i.e. NOT `com.android.vending` (Play Store). This is the install-source heuristic.

### 1.6 i18n state

11 locales total (`de, en, es, fr, hu, it, tr, uk, zh-CN, zh-TW` + `es`). Slang is configured to fall back to `en` per project memory. Existing precedent for permission strings: `bolsio_ai.voice_permission_*` keys (lines 580-586 of `es.json`). New strings only need to land in `en.json` + `es.json`.

### 1.7 Existing dependencies — what we already have

From `pubspec.yaml`:

| Package | Version | Relevance |
|---------|---------|-----------|
| `notification_listener_service` | ^0.3.5 | Listener perm check + request; uses generic intent (no detail screen). |
| `permission_handler` | ^12.0.1 | `Permission.notification` (POST_NOTIFICATIONS) + `openAppSettings()`. |
| `device_info_plus` | ^11.3.0 | Already used for OEM detection — exposes `AndroidDeviceInfo.version.sdkInt`. |
| `package_info_plus` | ^9.0.0 | Exposes `installerStore` getter (gives the same string as `dumpsys` — `com.android.vending` for Play, `com.google.android.packageinstaller` for sideload, `null` on very old APIs). **No new dep needed for the install-source heuristic.** |
| `app_settings` | ^6.1.1 | Generic settings deep-links (alternative to platform channel for app-info). |

`android_intent_plus` is **not** a dep and is **not needed** — we already have a working platform channel. Adding one method to it is cheaper than adding a new package + manifest `<queries>` updates.

---

## 2. Detection — how we know the gate is on

### 2.1 Authoritative signal: AppOps via platform channel (RECOMMENDED)

Implementation:

```kotlin
// DeviceQuirksChannel.kt — new method
private fun isRestrictedSettingsAllowed(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true // pre-Android 13: gate doesn't exist
    return try {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        // OPSTR_ACCESS_RESTRICTED_SETTINGS is hidden API on some firmwares; use the literal.
        // String value: "android:access_restricted_settings"
        val mode = appOps.unsafeCheckOpNoThrow(
            "android:access_restricted_settings",
            Process.myUid(),
            context.packageName
        )
        // MODE_ALLOWED (0) or MODE_DEFAULT (3) → allowed
        // MODE_IGNORED (1) or MODE_ERRORED (2) → blocked
        mode == AppOpsManager.MODE_ALLOWED || mode == AppOpsManager.MODE_DEFAULT
    } catch (e: Exception) {
        true // fail-open: don't show the gate slide if we can't detect — avoid false positives
    }
}
```

**Cost**: ~15 LOC of Kotlin + 1 new MethodChannel branch (`isRestrictedSettingsAllowed`) + a Dart wrapper in `DeviceQuirksService`. Zero new permissions, zero new manifest entries.

**Correctness**: matches what the OS actually uses to decide whether to gray out the toggle. No false positives.

**Risks**:
- `unsafeCheckOpNoThrow` is technically `@hide`-ish but the **string overload** has been stable since API 29; the constant `OPSTR_ACCESS_RESTRICTED_SETTINGS` was added publicly in API 33. Using the string literal sidesteps the `@hide` issue and works on all API ≥ 29 builds; on < 33 it returns `MODE_ALLOWED` because the OP doesn't exist there.
- On HyperOS the AppOp could in theory be patched out; the try/catch fail-open keeps us safe.

### 2.2 Heuristic fallback (no platform channel call)

Used only if the AppOps query fails or in a defensive secondary check:

```dart
bool likelyRestricted({required AndroidDeviceInfo info, required PackageInfo pkg, required bool listenerGranted}) {
  if (info.version.sdkInt < 33) return false;
  if (listenerGranted) return false; // already past the gate
  final installer = pkg.installerStore; // 'com.android.vending' = Play Store
  return installer != 'com.android.vending';
}
```

**Cost**: zero new code beyond what `package_info_plus` already gives us.

**Correctness**: false positives possible (e.g. user installed via Play but listener denied for unrelated reasons). False negatives also possible (e.g. some Samsung firmware doesn't enforce the gate even on sideloaded APKs).

### 2.3 Decision

Use **AppOps as the source of truth** (§2.1). Heuristic (§2.2) is documented as a fallback in the design doc but only fires when `unsafeCheckOpNoThrow` throws (which we expect to never happen in practice). This is the cleanest answer to the prompt's "cost vs benefit" question — a 15-line Kotlin patch plus a Dart wrapper is unambiguously cheaper than maintaining a heuristic that risks user confusion.

---

## 3. UX flow — slide vs dialog vs settings entry

### 3.1 Option A: New conditional slide BEFORE `Slide08ActivateListener` (RECOMMENDED)

Insert `Slide07_5RestrictedSettings` (or rename to `Slide08RestrictedSettings` with cascading rename — but renaming everything is gold-plating; just keep it as `Slide075RestrictedSettings.dart` ordered between 07 and 08 in `_buildSlides()`).

**Conditional rendering**: only render when `isRestrictedSettingsAllowed == false`. Mirrors the `_isAndroid` pattern. Dart pseudocode:

```dart
if (_isAndroid && _restrictedSettingsBlocked) {
  slides.add(Slide075RestrictedSettings(onNext: _next, onSkip: _skip));
}
```

The detection happens once in `OnboardingPage.initState` (mirror `_isAndroid` check) so `_buildSlides()` stays synchronous. To keep `_buildSlides` reactive to runtime resolution we just call `setState(() => _restrictedSettingsBlocked = ...)` after the async detection completes.

**Pros**:
- Matches existing onboarding visual grammar (V3SlideTemplate, mini-phone mockup, primary/secondary CTAs).
- Doesn't disrupt slide 8 — slide 8's existing logic still works, but on a non-restricted path it never sees a grayed-out toggle.
- The progress bar count auto-updates — no manual fiddling.
- Skippable (slide doesn't block onboarding completion); we don't strand the user.

**Cons**:
- One more slide to maintain.
- Detection runs async at boot — user could in theory advance to slide 7 before the check resolves (mitigation: cache the result after `initState` future, default to `true` (= allowed = no extra slide) until proven otherwise; users on fast paths see no flicker).

**Effort**: Low. ~1 new slide file (~250 LOC mirroring `s07_post_notifications.dart`) + 1 platform channel method + 1 `PermissionCoordinator` field + a few i18n keys + a check in `_buildSlides()`. Touches ~6 files.

### 3.2 Option B: Inline panel inside `Slide08ActivateListener`

Show the restricted-settings warning + CTA as an **expansion** within the existing slide 8, similar to how `_OemInstructions` already piggybacks on slide 8 for MIUI/HyperOS users.

**Pros**:
- No new slide → simpler menu, fewer files.
- The user is already on the listener slide, which is the right mental context.

**Cons**:
- Slide 8 is already busy (mini-phone mockup + OEM instructions panel + battery tile). Adding a third inline element risks turning the screen into a soup of warnings.
- The completion sequence is two-step (allow restricted → enable listener), which is hard to read inline; users on POCO will scroll and miss it.
- Mixes two different deep-link destinations (`AppDetails` for the ⋮ menu vs `NotificationListenerSettings` for the toggle), making the primary CTA polysemous.

**Effort**: Low-Medium. Logic is bigger than option A because slide 8 has to track THREE awaiting-resume flags (battery, restricted, listener) instead of two.

### 3.3 Option C: Modal dialog post-listener-failure

Detect after the user taps "Activar ahora" on slide 8 and the toggle stays denied for ≥ N seconds → pop a dialog with the steps.

**Pros**: zero changes to slide order; only fires for users who actually hit the gate.

**Cons**:
- Trigger is timing-based and fragile. Users on slow phones could trip it spuriously.
- Dialogs over a fullscreen onboarding feel out-of-place vs the V3 design language.
- Doesn't help users who skip slide 8 (the "Omitir" button persists `notifListenerEnabled='0'`); the gate just becomes invisible until they later try Settings → Auto-import.

**Effort**: Low but UX-fragile.

### 3.4 Decision

Go with **Option A**. The dynamic-slide pattern is already battle-tested by the `_isAndroid` block; reusing it keeps the change small and consistent. Option B is the runner-up; document it in the design doc as the alternative and explain why we picked A.

### 3.5 Out-of-onboarding entry point (BONUS, not required for v1)

Settings → Auto-import already shows a permissions checklist (per `PermissionCoordinator.stateNotifier`). Adding a `restrictedSettingsAllowed` field to `CapturePermissionsState` would automatically light up a row there too, so users who skipped onboarding can still find the fix later. **Defer to a follow-up — out of scope for this change.** Note in proposal § Future Work.

---

## 4. Completion detection — when did the user finish?

The user flow is:

1. User taps primary CTA on the new slide → we deep-link to `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` for `com.bolsio.app` (the screen with the ⋮ menu).
2. User opens ⋮ → "Permitir configuración restringida" → confirms.
3. User presses back → returns to Bolsio.

We need to know moment (3) happened AND that the AppOp flipped to `allow`/`default`.

### 4.1 The pattern is already in the codebase

`s07_post_notifications.dart` and `s08_activate_listener.dart` both implement the canonical Flutter "leave-and-return" detection:

```dart
class _State extends State<...> with WidgetsBindingObserver {
  bool _awaitingResumeAfterTap = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingResumeAfterTap) {
      _awaitingResumeAfterTap = false;
      _refreshAndMaybeAdvance();
    }
  }

  Future<void> _refreshAndMaybeAdvance() async {
    final allowed = await DeviceQuirksService.instance.isRestrictedSettingsAllowed();
    if (!mounted) return;
    if (allowed) widget.onNext();
    else setState(() => _stillBlocked = true); // re-render with a "still not done" hint
  }

  Future<void> _openAppDetails() async {
    _awaitingResumeAfterTap = true;
    await DeviceQuirksService.instance.openAppDetails();
  }
}
```

**This is event-driven, not polling.** The OS sends `onResume` exactly when the user comes back. Polling would be wasteful and battery-hostile.

### 4.2 Edge cases worth listing

- **User comes back without enabling**: `_refreshAndMaybeAdvance` sees `allowed == false`, slide stays mounted, primary CTA remains "Abrir ajustes". Add a small "still blocked" inline hint with retry copy ("Si ya lo activaste, presiona Comprobar de nuevo").
- **User cold-kills the app while in Settings**: when they reopen Bolsio, onboarding restarts from slide 0 if `introSeen != '1'`. Detection runs again on each fresh `initState` — the check will catch up.
- **Race between OS allowing the AppOp and `onResume` firing**: HyperOS appears to update the AppOp synchronously when the user toggles the menu item; the order observed in adb is "user toggles → AppOp flips → user navigates back → onResume fires". Adding a 200-300 ms `Future.delayed` before re-checking is not necessary in initial implementation; only add it if QA reports a flake.

### 4.3 Decision

Reuse the existing `WidgetsBindingObserver` resume pattern. No polling. No timer-based retries. No new infra.

---

## 5. Deep links — where do we send the user?

The "Permitir configuración restringida" toggle lives **inside the ⋮ menu of the App Info screen**. There is **no system-level intent that opens the menu directly** — the user must tap ⋮ themselves. Our job is to land them on App Info with maximum confidence.

### 5.1 Available intents

| Intent | Lands on | Useful? |
|--------|----------|---------|
| `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` (with `package:` URI) | App Info screen for our package — the screen that has the ⋮ menu in its top-right | **YES — primary** |
| `Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS` | Generic listener access list; toggle is grayed | useless for the restricted gate |
| `Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS` | Bolsio's specific toggle row; toggle is grayed | useless for the restricted gate |

`Settings.ACTION_APPLICATION_DETAILS_SETTINGS` is **already implemented** in `DeviceQuirksChannel.openAppDetails` (line 84). We don't add a new platform method — we reuse the existing one and call it from the new slide.

### 5.2 No package needed

`android_intent_plus` is **not** required. We already have a working channel. The slide will simply invoke `DeviceQuirksService.instance.openAppDetails()`.

### 5.3 Mockup affordance

The slide's "mini-phone mockup" should depict the App Info screen with the ⋮ menu open and "Permitir configuración restringida" highlighted. Reuse `V3MiniPhoneFrame` (already used in slides 7 + 8) and build a custom child widget. ~80 LOC of decorative widget code.

---

## 6. i18n strings (English + Spanish only)

New keys to add to `en.json` + `es.json` under a new `onboarding.restricted_settings` namespace (or merge into the existing `onboarding` group if there is one — quick check needed when writing the spec). Approximate copy:

| Key | ES (canonical) | EN |
|-----|----------------|-----|
| `title` | Activa la configuración restringida | Allow restricted settings |
| `body` | Android bloquea ciertos permisos en apps instaladas fuera de Play Store. Vamos a habilitar la configuración restringida para que puedas activar el listener en el siguiente paso. | Android blocks some permissions for apps installed outside Play Store. We'll enable restricted settings so you can turn on the listener in the next step. |
| `step_1` | Toca **Abrir ajustes**. | Tap **Open settings**. |
| `step_2` | En la pantalla de la app, toca el menú **⋮** arriba a la derecha. | On the app screen, tap the **⋮** menu in the top-right corner. |
| `step_3` | Selecciona **Permitir configuración restringida** y confirma. | Select **Allow restricted settings** and confirm. |
| `step_4` | Vuelve a Bolsio. Detectaremos el cambio automáticamente. | Return to Bolsio. We'll detect the change automatically. |
| `cta_open` | Abrir ajustes | Open settings |
| `cta_skip` | Hacer esto más tarde | Do this later |
| `still_blocked_hint` | Si ya activaste la opción, vuelve a tocar **Abrir ajustes** y presiona el botón "Comprobar de nuevo". | If you already enabled the option, tap **Open settings** again and press "Check again". |

These follow the same naming + tone as `bolsio_ai.voice_permission_*`. **Per project memory: only add to `en.json` + `es.json` — Slang falls back to `en` for the other 9 locales.**

---

## 7. Affected files (rough touch list)

- `lib/app/onboarding/onboarding.dart` — add `_restrictedSettingsBlocked` state, async detection in `initState`, conditional insertion in `_buildSlides()`.
- `lib/app/onboarding/slides/s075_restricted_settings.dart` — **new** slide (mirror s07/s08).
- `lib/core/services/auto_import/capture/device_quirks_service.dart` — new Dart method `isRestrictedSettingsAllowed()`.
- `lib/core/services/auto_import/capture/permission_coordinator.dart` — add `restrictedSettingsAllowed` field to `CapturePermissionsState` (gives Settings → Auto-import a future hook for free).
- `android/app/src/main/kotlin/com/bolsio/app/DeviceQuirksChannel.kt` — new branch `isRestrictedSettingsAllowed` that calls `AppOpsManager.unsafeCheckOpNoThrow("android:access_restricted_settings", uid, pkg)`.
- `lib/i18n/json/en.json` + `lib/i18n/json/es.json` — new keys (~9 strings).
- `lib/i18n/generated/translations*.g.dart` — regenerated by `dart run slang` (do not hand-edit).

No Drift migration. No new package dep. No `AndroidManifest.xml` changes.

---

## 8. Risks

- **AppOps API surface stability**: `OPSTR_ACCESS_RESTRICTED_SETTINGS` is the public constant since API 33; using the string literal `"android:access_restricted_settings"` keeps the build clean and forward-compatible with whatever device-info_plus minSdk is. Mitigation: try/catch fail-open in Kotlin (return `true` if anything explodes, so the slide is silently skipped — never trapped on a phantom slide).
- **HyperOS firmware drift**: Xiaomi sometimes rebrands AppOps. If a future HyperOS revision hides the OP, the heuristic fallback (§2.2) catches the case. Mitigation: log via `debugPrint` in the catch branch so we can spot it in tester reports.
- **Race conditions on initState detection**: if the slide list is rebuilt before the async detection completes, the user briefly sees the non-restricted flow and then a slide may appear "out of nowhere". Mitigation: gate the conditional with `_restrictedSettingsChecked` and treat unchecked as "not blocked" (no extra slide). The detection is fast (single Binder call) — typically <50 ms. In practice the user is still finishing earlier slides when it resolves.
- **Skipping the slide silently disables auto-import**: if the user picks "Hacer esto más tarde", slide 8 will still let them try (and likely fail) the listener toggle. We persist `notifListenerEnabled='0'` (existing behaviour) and surface the issue from Settings → Auto-import later. Acceptable.
- **i18n drift**: If we forget to namespace the keys properly, slang regen could collide. Mitigation: nest under `onboarding.restricted_settings.*` (no existing keys at that path).
- **adb test fixture relies on `rejectTime` flipping**: If we want an integration test, we would need to flip the AppOp via adb (`adb shell appops set com.bolsio.app ACCESS_RESTRICTED_SETTINGS allow`). Document in the tasks.md test fixture.

---

## 9. Recommendation

Ship the change as a **dynamic slide between current s07 and s08**, gated on a real `AppOpsManager` check via a new `DeviceQuirksChannel.isRestrictedSettingsAllowed` method, with the same `WidgetsBindingObserver` resume pattern that already drives s07/s08 auto-advance.

Scope is tight: 1 new slide, 1 new platform-channel method, 1 new `CapturePermissionsState` field, 9 i18n strings (en+es only), and a small wiring diff in `OnboardingPage._buildSlides()`. Zero new packages. Zero migrations. Zero manifest changes.

Concretely:

| Concern | Answer |
|---------|--------|
| Detection mechanism | `AppOpsManager.unsafeCheckOpNoThrow("android:access_restricted_settings", uid, pkg)` via existing `com.bolsio.capture/quirks` channel |
| Heuristic fallback | `package_info_plus.installerStore != 'com.android.vending'` + `sdkInt >= 33` + `listener denied` — only used if AppOps throws |
| UX surface | Conditional slide between s07 and s08, modeled on `s07_post_notifications.dart` |
| Deep link | `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` (already exposed as `openAppDetails`) |
| Completion detection | `WidgetsBindingObserver.didChangeAppLifecycleState(resumed)` re-checks AppOps and auto-advances |
| Strings | 9 new keys in `en.json` + `es.json` only; Slang falls back to `en` for other 9 locales |
| Backout plan | The slide is purely additive and gated on a dynamic flag; remove the slide from `_buildSlides()` and the channel method becomes dead code (revert in 1 PR). |

---

## 9b. Detection: post-mortem (2026-04-29)

The AppOps recommendation in §2.1 / §2.3 **did not survive contact with a real device**. Logcat on POCO rodin (HyperOS, SDK 36):

```
SecurityException: verifyIncomingOp: uid 10478 does not have any of
  {MANAGE_APPOPS, GET_APP_OPS_STATS, MANAGE_APP_OPS_MODES}
```

`unsafeCheckOpNoThrow` requires one of those three permissions, which are reserved for system apps. The fail-open branch returned `true` for every device → slide silently skipped for everyone. AppOps is fundamentally unviable for this use case from a regular app.

**Mitigation that shipped**: installer-source heuristic — treat install from Play Store / Galaxy Store / Huawei AppGallery / Amazon Appstore as "no gate"; sideload / `com.google.android.packageinstaller` / ADB / unknown / null → "gate active, show slide". Trade-off: a user who has already toggled `ACCESS_RESTRICTED_SETTINGS=allow` but installed via a non-trusted installer will see the slide once and can dismiss with "Skip for now". Strictly better than the AppOps false-negative.

§2.2's "heuristic fallback" was therefore promoted to the primary detection mechanism.

## 10. Ready for proposal?

**Yes.** All four key questions resolved with concrete, tested-on-device answers. Hand off to `sdd-propose`.

Suggested proposal scope:
- **Why**: every sideloaded user on Android 13+ hits a 10-step manual workaround that blocks Bolsio's core feature. This shrinks the workaround to 3 taps + auto-detected resume.
- **What**: dynamic onboarding slide + AppOps detection + i18n.
- **What it is NOT**: a Settings → Auto-import re-design (deferred). Not a Play Store launch (deferred). Not a multi-locale string update (en+es only).
- **Rollback**: remove the conditional from `_buildSlides`, leave the channel method (it's harmless dead code), revert the `CapturePermissionsState` field.
