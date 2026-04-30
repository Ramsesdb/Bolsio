# Design: Restricted Settings Onboarding Slide

## Technical Approach

Insert a dynamic, conditional onboarding step that detects Android's `ACCESS_RESTRICTED_SETTINGS` AppOps gate and walks the user through enabling it before they reach the notification-listener slide. The step is rendered by a single shared widget (`V3RestrictedSettingsStep`) consumed by both `OnboardingPage` (as `Slide075`) and `ReturningUserFlow` (as a new intermediate step). Detection is a single Binder call exposed through the existing `com.bolsio.capture/quirks` MethodChannel; lifecycle-resume re-evaluation reuses the canonical `WidgetsBindingObserver` pattern already used by `s07_post_notifications.dart` and `s08_activate_listener.dart`. Zero new packages, zero migrations, zero manifest changes.

## Architecture Overview

### Component diagram

```
┌──────────────────────────────────┐
│ MainActivity.kt                   │
│ DeviceQuirksChannel               │
│  ├─ isIgnoringBatteryOptimizations│
│  ├─ openAppDetails                │
│  └─ isRestrictedSettingsAllowed ●NEW
└──────────┬────────────────────────┘
           │ MethodChannel "com.bolsio.capture/quirks"
           ▼
┌──────────────────────────────────┐
│ DeviceQuirksService (Dart)        │
│  └─ isRestrictedSettingsAllowed() ●NEW (returns true on error)
└──────────┬────────────────────────┘
           │
           ▼
┌──────────────────────────────────┐
│ CapturePermissionsState           │
│  └─ restrictedSettingsAllowed: bool ●NEW
└──────────┬────────────────────────┘
           │ Consumed by both hosts (state field; UI surfacing deferred)
           ▼
┌─────────────────────┐    ┌─────────────────────┐
│ OnboardingPage      │    │ ReturningUserFlow   │
│  _buildSlides()     │    │  _step state machine│
│  + Slide075 (cond.) │    │  + restricted step  │
└──────────┬──────────┘    └──────────┬──────────┘
           │                          │
           └────────┬─────────────────┘
                    ▼
        ┌──────────────────────────┐
        │ V3RestrictedSettingsStep │
        │  (shared, chrome-less)   │
        │  WidgetsBindingObserver  │
        │  CTAs + still-blocked    │
        └──────────────────────────┘
```

### Data flow

```
Host.initState
   │
   ├─ DeviceQuirksService.isRestrictedSettingsAllowed()  ── async
   │       └─ false ─→ setState(_restrictedSettingsBlocked = true)
   │                       └─ rebuild slide/step list with extra step
   │
   ▼ user reaches step
V3RestrictedSettingsStep
   │
   ├─ User taps primary CTA → DeviceQuirksService.openAppDetails()
   │                          → _awaitingResume = true
   │
   ├─ App lifecycle: resumed && _awaitingResume
   │       ├─ recheck isRestrictedSettingsAllowed()
   │       │       ├─ allowed? → onContinue()  (auto-advance)
   │       │       └─ blocked? → setState(_stillBlocked = true)
   │       └─ _awaitingResume = false
   │
   └─ User taps "Skip for now" → onContinue()
```

## Architecture Decisions

| Decision | Choice | Alternatives | Rationale |
|----------|--------|--------------|-----------|
| Detection mechanism | Kotlin `AppOpsManager.unsafeCheckOpNoThrow("android:access_restricted_settings", uid, pkg)` via existing channel | (a) `package_info_plus.installerStore` heuristic; (b) try-toggle-and-observe | AppOps is the OS's own source of truth — zero false positives. Heuristic kept only as fail-open default if the call throws. |
| Code reuse for two hosts | Single shared `V3RestrictedSettingsStep` widget (chrome-less body), wrapped by each host | Duplicate ~250 LOC into each flow | Halves maintenance footprint when copy/UX evolves. Chrome (progress bar in onboarding, none in returning) stays in host. |
| SDK gating in Kotlin | `Build.VERSION.SDK_INT < 31` → return `true` (fail-open) | Gate at SDK 33 (when UX shipped) | OPSTR was added in API 31 but UX behavior shipped in 33; on API 31–32 the OP exists but is inert and returns `MODE_DEFAULT` → still allowed. Single SDK check covers both. |
| Failure mode | Fail-open (return `true` = no extra step) on any exception | Fail-closed (always show the step on error) | A phantom step on a non-restricted device is worse UX than missing it on an exotic one. Skipping the gate degrades to status quo. |
| Lifecycle observer location | Inside `V3RestrictedSettingsStep` itself | In each host | Keeps the recheck logic colocated with the UI that depends on it. Mirrors `s07`/`s08` precedent. |
| Back-pill visibility | Widget prop `showBackPill` (default `true`) | Always show | `OnboardingPage` has a global header back-pill; `ReturningUserFlow` does not, and going back to the welcome-back hero feels redundant. |
| Detection caching | Re-evaluate on every host `initState` and on every lifecycle resume | Cache once for app session | The user fixing the gate IS the state change we want to observe. Caching would defeat auto-advance. |

## Kotlin Platform Channel Design

### Method signature

- Channel: `com.bolsio.capture/quirks` (existing)
- Method name: `isRestrictedSettingsAllowed`
- Returns: `Boolean` (`true` = allowed, `false` = blocked)

### Implementation sketch (~15 LOC)

```kotlin
private fun isRestrictedSettingsAllowed(context: Context): Boolean {
    // OPSTR_ACCESS_RESTRICTED_SETTINGS was introduced in API 31 (Android 12),
    // but the OS-level UX gate (graying out the listener toggle) is from API 33.
    // Below 31 the OP doesn't exist — fail-open with `true`.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
    return try {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        // Use the string literal — OPSTR_ACCESS_RESTRICTED_SETTINGS is @hide-ish on
        // some firmwares; the raw string is stable since API 29.
        val mode = appOps.unsafeCheckOpNoThrow(
            "android:access_restricted_settings",
            Process.myUid(),
            context.packageName,
        )
        mode == AppOpsManager.MODE_ALLOWED || mode == AppOpsManager.MODE_DEFAULT
    } catch (e: Exception) {
        Log.d("Bolsio", "isRestrictedSettingsAllowed failed (fail-open): $e")
        true
    }
}
```

Wire-up in the `setMethodCallHandler` switch:

```kotlin
"isRestrictedSettingsAllowed" -> result.success(isRestrictedSettingsAllowed(context))
```

## Dart-side Design

### `DeviceQuirksService` extension

```dart
/// Best-effort: is the OS willing to let us toggle the notification listener
/// for this app? Returns `true` on iOS, on platform errors, and on any device
/// where the AppOp is `MODE_ALLOWED` or `MODE_DEFAULT`. Returns `false` only
/// when AppOps explicitly reports the gate is closed.
Future<bool> isRestrictedSettingsAllowed() async {
  if (!Platform.isAndroid) return true;
  try {
    final res = await _channel.invokeMethod<bool>('isRestrictedSettingsAllowed');
    return res ?? true;
  } catch (e) {
    debugPrint('DeviceQuirksService: isRestrictedSettingsAllowed error: $e');
    return true; // fail-open
  }
}
```

### `CapturePermissionsState` field

Add `final bool restrictedSettingsAllowed;` (default `true` in `.initial()`), update `copyWith`, `==`, and `hashCode`. The field is added now to give the deferred Settings → Auto-import row a free hook later — no UI consumes it in this change beyond the shared widget's lifecycle recheck calling `DeviceQuirksService` directly.

### Host integration — `OnboardingPage`

```dart
class _OnboardingPageState extends State<OnboardingPage> ... {
  bool _isAndroid = false;
  bool _restrictedSettingsBlocked = false; // ●NEW

  @override
  void initState() {
    super.initState();
    _isAndroid = !kIsWeb && Platform.isAndroid;
    _resolveRestrictedSettings();
  }

  Future<void> _resolveRestrictedSettings() async {
    if (!_isAndroid) return;
    final allowed = await DeviceQuirksService.instance.isRestrictedSettingsAllowed();
    if (!mounted || allowed) return;
    setState(() => _restrictedSettingsBlocked = true);
  }

  List<Widget> _buildSlides() {
    final slides = <Widget>[
      // ... s01..s07
    ];
    if (_isAndroid && _restrictedSettingsBlocked) {
      slides.add(Slide075RestrictedSettings(onNext: _next));
    }
    slides.add(Slide08ActivateListener(...));
    // ...
  }
}
```

### Host integration — `ReturningUserFlow`

```dart
class _ReturningUserFlowState extends State<ReturningUserFlow> {
  // 0 = welcome back; 1 = restricted-settings (conditional); 2 = activate listener.
  // When _restrictedSettingsBlocked == false, step 1 is skipped (1 → 2 directly).
  int _step = 0;
  late final bool _isAndroid;
  bool _restrictedSettingsBlocked = false; // ●NEW
  bool _restrictedSettingsResolved = false; // ●NEW guards welcome-CTA

  @override
  void initState() {
    super.initState();
    _isAndroid = !kIsWeb && Platform.isAndroid;
    _resolveRestrictedSettings();
  }

  Future<void> _resolveRestrictedSettings() async {
    if (!_isAndroid) {
      setState(() => _restrictedSettingsResolved = true);
      return;
    }
    final allowed = await DeviceQuirksService.instance.isRestrictedSettingsAllowed();
    if (!mounted) return;
    setState(() {
      _restrictedSettingsBlocked = !allowed;
      _restrictedSettingsResolved = true;
    });
  }

  Future<void> _advanceFromWelcome() async {
    // ... existing fast-path checks
    if (_restrictedSettingsBlocked) {
      setState(() => _step = 1); // restricted-settings step
      return;
    }
    setState(() => _step = 2); // jump straight to listener
  }
}
```

The welcome-back primary CTA shows a small inline spinner while `_restrictedSettingsResolved == false` (rare; resolves in <50 ms).

### Shared widget API

```dart
class V3RestrictedSettingsStep extends StatefulWidget {
  const V3RestrictedSettingsStep({
    super.key,
    required this.onContinue,    // skip OR auto-advance success
    required this.onOpenAppInfo, // primary CTA tap (deep-link)
    this.showBackPill = true,    // false in ReturningUserFlow
  });

  final VoidCallback onContinue;
  final VoidCallback onOpenAppInfo;
  final bool showBackPill;
  // ...
}
```

Internal state:
- `bool _awaitingResume = false`
- `bool _stillBlocked = false` (set after first failed resume recheck)
- `WidgetsBindingObserver`: on `resumed && _awaitingResume`, call `DeviceQuirksService.instance.isRestrictedSettingsAllowed()` → if `true`, `widget.onContinue()`; else `setState(_stillBlocked = true)`.

## UX Details

- Visual mirror: `s07_post_notifications.dart` — same `V3SlideTemplate`, `V3MiniPhoneFrame`, primary/secondary button stack.
- Primary CTA: filled button, label `t.onboarding.restrictedSettings.ctaPrimary` ("Open app info" / "Abrir información de la app").
- Secondary CTA: text button, label `t.onboarding.restrictedSettings.ctaSkip`.
- Body: 3 numbered steps depicted inline (text only, no screenshot — keeps APK lean and survives OEM UI drift better than a hardcoded image).
- Mini-phone mockup: a stylized App Info screen with the kebab `⋮` menu open and "Allow restricted settings" highlighted. ~80 LOC of decorative widget code, drawn with native Flutter primitives.
- "Still blocked" hint: small italic body-small text in `colorScheme.onSurfaceVariant`, rendered only after `_stillBlocked == true`. One line, no troubleshooting block.
- Back-pill: hosted by `V3SlideTemplate` when `showBackPill == true`. `OnboardingPage` shows it; `ReturningUserFlow` hides it (welcome hero is just one step back, not worth a dedicated affordance).

## i18n Keys

Added under `onboarding.restricted_settings.*` in `lib/i18n/json/en.json` and `lib/i18n/json/es.json` only (Slang falls back to `en` for the other 9 locales).

| Key | ES (canonical) | EN |
|-----|----------------|-----|
| `title` | Permite la configuración restringida | Allow restricted settings |
| `subtitle` | Android bloquea ciertos permisos en apps instaladas fuera de Play Store. Lo arreglamos en 3 toques. | Android blocks some permissions for apps installed outside Play Store. We'll fix it in 3 taps. |
| `step1` | Toca el menú **⋮** arriba a la derecha. | Tap the **⋮** menu in the top-right. |
| `step2` | Selecciona **Permitir configuración restringida**. | Select **Allow restricted settings**. |
| `step3` | Activa el toggle y vuelve a Bolsio. | Toggle it on and return to Bolsio. |
| `cta_primary` | Abrir información de la app | Open app info |
| `cta_skip` | Hacer esto más tarde | Skip for now |
| `still_blocked_hint` | Si ya lo activaste, vuelve a abrir la información de la app. | If you already enabled it, open app info again. |
| `success_toast` | Listo, configuración desbloqueada | Done, settings unlocked |

`success_toast` is optional — current design auto-advances silently without a toast. Key reserved for future use; not consumed in v1.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `android/app/src/main/kotlin/com/bolsio/app/DeviceQuirksChannel.kt` | Modify | Add `isRestrictedSettingsAllowed` method (~15 LOC) and channel branch. |
| `lib/core/services/auto_import/capture/device_quirks_service.dart` | Modify | Add `isRestrictedSettingsAllowed()` Dart wrapper. |
| `lib/core/services/auto_import/capture/permission_coordinator.dart` | Modify | Add `restrictedSettingsAllowed` field to `CapturePermissionsState` (with `copyWith`, `==`, `hashCode`, `.initial()`). |
| `lib/app/onboarding/widgets/v3_restricted_settings_step.dart` | Create | Shared step widget with lifecycle observer + CTAs + still-blocked hint. |
| `lib/app/onboarding/slides/s075_restricted_settings.dart` | Create | Onboarding slide that wraps the shared widget in `V3SlideTemplate`. |
| `lib/app/onboarding/onboarding.dart` | Modify | Async detection in `initState`; conditional insertion in `_buildSlides()`. |
| `lib/app/auth/returning_user_flow.dart` | Modify | Async detection in `initState`; expand `_step` machine to 0/1/2; render shared widget at step 1. |
| `lib/i18n/json/en.json` | Modify | Add 9 keys under `onboarding.restricted_settings.*`. |
| `lib/i18n/json/es.json` | Modify | Add 9 keys (canonical Spanish). |
| `lib/i18n/generated/translations*.g.dart` | Regenerate | `dart run slang` after JSON edits. |

## Testing Strategy

| Layer | What to Test | Approach |
|-------|--------------|----------|
| Unit | `DeviceQuirksService.isRestrictedSettingsAllowed` returns `true` on `PlatformException` and on iOS | Mock `MethodChannel` with a thrown exception and a non-Android platform flag. |
| Unit | `CapturePermissionsState.copyWith` preserves `restrictedSettingsAllowed` and `==` honors it | Standard equality/copy test pattern (existing precedent in same file). |
| Widget | `V3RestrictedSettingsStep` renders title/subtitle/CTAs; tapping primary calls `onOpenAppInfo`; tapping skip calls `onContinue`; `showBackPill: false` hides the back-pill | `pumpWidget` + `tap` + assertion on callback invocation count. |
| Widget | Lifecycle resume re-evaluation: stub `DeviceQuirksService` to return `true` on second call → assert `onContinue` fires | Drive `WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed)`; verify the auto-advance path. |
| Manual smoke | POCO rodin (HyperOS) gate currently `ignore` — verify slide appears in `OnboardingPage` first-install path AND in `ReturningUserFlow` (Google sign-in with Firebase data); CTA opens App Info; toggling "Allow restricted settings" + back-press auto-advances | Per session test fixture; verify in both Android first-install and returning-user paths. |
| Manual smoke | Play Store-equivalent simulation: `adb shell appops set com.bolsio.app ACCESS_RESTRICTED_SETTINGS allow` → re-enter onboarding → verify slide does NOT render in any path | Side-by-side check vs the blocked baseline. |
| Integration / E2E | NOT in scope (no full E2E rig exists yet); deferred. |

`flutter test` shall pass; `flutter analyze` shall be clean. Per project memory (Bolsio tests rule): `flutter test` is NOT run inside each tanda — only `flutter analyze`. Tests run as a final pass.

## Migration / Rollout

No migration required. Purely additive feature gated on a runtime check. No Drift schema changes, no SharedPreferences key additions, no manifest changes. Disabling the feature is a one-PR revert (see proposal § Rollback).

## Detection: post-mortem

The AppOps approach above (`unsafeCheckOpNoThrow("android:access_restricted_settings", uid, pkg)`) **failed in production** on real devices. Logcat from POCO rodin (HyperOS, SDK 36) showed:

```
SecurityException: verifyIncomingOp: uid 10478 does not have any of
  {MANAGE_APPOPS, GET_APP_OPS_STATS, MANAGE_APP_OPS_MODES}
```

Root cause: those three permissions are system-app-only; regular apps cannot query the AppOp regardless of how it's invoked. The fail-open `catch` branch then returned `true` for every device, silently skipping the slide for the very users it was designed to help.

**Replacement**: installer-source heuristic in `DeviceQuirksChannel.isRestrictedSettingsAllowed`. Treats install via `com.android.vending` / `com.google.android.feedback` / `com.huawei.appmarket` / `com.amazon.venezia` / `com.sec.android.app.samsungapps` as "no gate"; everything else (sideload, ADB, unknown installer, null) is treated as gated → slide shown.

**Trade-off**: false-positive when a user grants `ACCESS_RESTRICTED_SETTINGS=allow` but installed via a non-trusted installer — they see the slide once and can dismiss with "Skip for now". Strictly better than the false-negative AppOps behavior that hid the slide from every restricted user.

## Post-mortem addendum: auto-advance removed, manual confirmation + vendor variant

A second iteration after on-device testing on POCO rodin (HyperOS) surfaced two issues that forced a UX pivot:

1. **Auto-advance never fires.** The replacement detection (`isRestrictedSettingsAllowed`) is an installer-source heuristic — immutable for the lifetime of the install. The `WidgetsBindingObserver` resume re-check therefore returns the same `false` after the user enables the toggle, leaving the user wedged on the slide.
2. **Step copy is wrong on Xiaomi.** MIUI/HyperOS App info has no top-right kebab — the "Permitir ajustes restringidos" toggle sits at the bottom of the scroll, with a different label.

**Resolution**:
- Removed the lifecycle re-detection + `still_blocked_hint` rendering. The primary CTA now flips from "Open app info" → "Done, continue" once the user returns from Settings (tracked by `_didTapOpenAppInfo` + `_userReturnedFromSettings`). Manual confirmation is unavoidable given the heuristic limitation.
- Added a Kotlin `getDeviceVendor()` channel method (`'xiaomi'` for Xiaomi/Redmi/POCO, `'stock'` otherwise) and a Dart wrapper. The widget renders `step1_xiaomi`/`step2_xiaomi` for Xiaomi devices.
- New i18n keys (en+es only): `step1_xiaomi`, `step2_xiaomi`, `cta_done`. The `still_blocked_hint` and `success_toast` keys remain in the JSON but are no longer consumed.

## Open Questions

All locked. Open questions from the proposal phase have been resolved by user confirmation:
- Slide filename: `s075_restricted_settings.dart` (no cascading rename) ✅
- i18n namespace: `onboarding.restricted_settings.*`, en+es only ✅
- Still-blocked hint: minimalist 1-line ✅
- Settings → Auto-import surfacing: deferred (only the state field lands now) ✅
- Shared widget vs duplicate: shared widget ✅
- Back-pill visibility: visible in `OnboardingPage`, hidden in `ReturningUserFlow` ✅
