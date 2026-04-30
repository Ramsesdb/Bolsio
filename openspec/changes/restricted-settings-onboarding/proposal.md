# Proposal: Restricted Settings Onboarding Slide

## Intent

Every Bolsio user who sideloads the APK on Android 13+ (and especially on HyperOS / POCO devices) hits Android's `ACCESS_RESTRICTED_SETTINGS` gate when they try to enable the notification listener. The toggle is grayed out, the flow cannot auto-advance, and users have to discover an undocumented 8-step workaround (App Info -> kebab menu -> "Allow restricted settings") on their own. Until Bolsio ships on Play Store, this gate blocks the auto-import core feature for 100% of sideloaded installs.

This change inserts a dynamic "fix the gate" step that detects the gate, walks the user through it in three taps, and auto-advances when they return — and ensures it appears **in every flow that leads to the notification-listener permission**, not just the first-install onboarding.

## Scope

### In Scope

- New conditional slide between `s07_post_notifications` and `s08_activate_listener` in the main onboarding (`OnboardingPage`), rendered only when the AppOps query reports the gate is active.
- **Coverage of every entry point that leads to the notification-listener permission**:
  - **First-install onboarding** — `WelcomeScreen._continueWithoutAccount` and `WelcomeScreen._signInWithGoogle` (when Firebase is empty) push `OnboardingPage`. Covered automatically by the new conditional slide in `OnboardingPage._buildSlides()`.
  - **Returning Google user mini-flow** — `WelcomeScreen._signInWithGoogle` pushes `ReturningUserFlow` when `pulledAccounts > 0` (Firebase had data). This is the flow the user observed firsthand: a 2-step compact widget (welcome-back hero + `_ActivateListenerStep`) at `lib/app/auth/returning_user_flow.dart`. **NOT** funneled through `OnboardingPage`, so it requires its own conditional gate-fix step injected before `_ActivateListenerStep` (or wrapped into a 3-step flow when blocked).
  - **Login / signup pages** (`lib/app/auth/login_page.dart`, `lib/app/auth/signup_page.dart`) — both set `onboarded='1'` and rely on the router (`InitialPageRouteNavigator` in `main.dart`) to push `OnboardingPage` next. Covered by the `OnboardingPage` patch.
  - **Router fallback** — `InitialPageRouteNavigator` (main.dart line 647) routes any `onboarded && !introSeen` user to `OnboardingPage`. Covered by the `OnboardingPage` patch.
- **Distinct flows confirmed**: there is NOT a single shared `OnboardingPage`. `ReturningUserFlow` is a separate widget with its own listener-permission step, so the scope expands to patch BOTH.
- Detection via a new `isRestrictedSettingsAllowed` method on the existing `com.bolsio.capture/quirks` MethodChannel, using `AppOpsManager.unsafeCheckOpNoThrow("android:access_restricted_settings", ...)` with a try/catch fail-open.
- New `restrictedSettingsAllowed` field on `CapturePermissionsState` (free hook for future Settings -> Auto-import surfacing).
- Primary CTA deep-links to `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` via the existing `openAppDetails` channel method.
- Lifecycle-resume completion detection (reusing the `WidgetsBindingObserver` pattern from s07/s08 and `_ActivateListenerStep`); auto-advance on success, "still blocked" inline hint on failure.
- 9 new i18n keys under `onboarding.restricted_settings.*` in `en.json` + `es.json` only (Slang falls back to `en` for the other 9 locales).
- A **shared** `RestrictedSettingsStep` widget (or factored predicate + slide-builder) reused by both `OnboardingPage` and `ReturningUserFlow` to avoid duplicating the ~250 LOC.

### Out of Scope

- Play Store distribution (separate concern; this change is the bridge until then).
- Surfacing the new permission row in Settings -> Auto-import (`capture_permissions.page.dart`) (deferred follow-up; the `CapturePermissionsState` field is added now to make it free later).
- Automatic install-source heuristic beyond the AppOps query (documented as a defensive fallback only; not implemented in v1).
- iOS support (no equivalent gate exists on iOS).
- Backporting to onboarding v1 (already replaced by v2).

## Approach

Reuse the conditional-slide pattern that already gates the Android-only auto-import block (`_isAndroid`). Add a parallel `_restrictedSettingsBlocked` flag, resolved asynchronously in `OnboardingPage.initState` and in `ReturningUserFlow.initState`, defaulting to `false` (no extra step) until proven otherwise. Factor the slide UI into a shared widget (`RestrictedSettingsStep` or similar) that both flows mount: in `OnboardingPage` it sits as `Slide075` between s07 and s08; in `ReturningUserFlow` it becomes a new `_step = 1` ahead of the existing `_ActivateListenerStep` (renumbered to `_step = 2`). Mirrors `s07_post_notifications.dart` structurally (same `V3SlideTemplate`, same `V3MiniPhoneFrame`, same observer-based auto-advance). Zero new packages, zero migrations, zero manifest changes.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/app/onboarding/onboarding.dart` | Modified | Async detection in `initState`; conditional insertion in `_buildSlides()`. |
| `lib/app/onboarding/slides/s075_restricted_settings.dart` | New | Conditional slide (~250 LOC, mirrors s07). Wraps the shared widget. |
| `lib/app/onboarding/widgets/v3_restricted_settings_step.dart` | New | Shared step widget consumed by both `OnboardingPage` and `ReturningUserFlow`. Owns the detection + lifecycle-resume + CTA + "still blocked" hint. |
| `lib/app/auth/returning_user_flow.dart` | Modified | Add async gate detection in `initState`; expand state machine to render the shared restricted-settings step before `_ActivateListenerStep` when `_restrictedSettingsBlocked == true`. |
| `lib/core/services/auto_import/capture/device_quirks_service.dart` | Modified | New `isRestrictedSettingsAllowed()` Dart wrapper. |
| `lib/core/services/auto_import/capture/permission_coordinator.dart` | Modified | Add `restrictedSettingsAllowed` field to `CapturePermissionsState`. |
| `android/app/src/main/kotlin/com/bolsio/app/DeviceQuirksChannel.kt` | Modified | New `isRestrictedSettingsAllowed` MethodChannel branch (~15 LOC). |
| `lib/i18n/json/en.json`, `lib/i18n/json/es.json` | Modified | 9 new keys under `onboarding.restricted_settings.*`. |
| `lib/i18n/generated/translations*.g.dart` | Regenerated | Via `dart run slang`. |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `unsafeCheckOpNoThrow` throws on a quirky firmware | Low | Try/catch fail-open: return `true` (= allowed = no extra slide) on any exception. User sees normal flow; no phantom slide. |
| Async detection resolves after user reaches s07, slide pops in late | Low | Detection is a single Binder call (~50 ms); user is still on early slides. Default to "not blocked" until resolved. |
| `ReturningUserFlow` resolves detection after the user already tapped "Continuar" past the welcome-back hero | Low | Detection fires in `initState` (parallel to existing permission probe in `_advanceFromWelcome`); both must complete before the welcome-back primary CTA can advance. Show a tiny inline spinner on the CTA if either is still pending (rare on fresh resume). |
| User picks "Hacer esto más tarde" -> listener still fails on next step | Medium | Existing s08 / `_ActivateListenerStep` `Omitir` paths persist `notifListenerEnabled='0'`; user can re-enter from Settings -> Auto-import (existing behavior). Acceptable. |
| HyperOS firmware drift renames the AppOp | Low | Heuristic fallback (`installerStore != 'com.android.vending'` + `sdkInt >= 33` + `listener denied`) documented in design doc as defensive secondary, only fires if AppOps throws. |
| Shared widget grows divergent needs between the two flows (chrome differs: `OnboardingPage` has progress bar, `ReturningUserFlow` does not) | Medium | Keep the shared widget chrome-less (just the body). Each host wraps it in its own `V3SlideTemplate` / standalone `Padding` so progress-bar concerns stay outside. |

## Rollback Plan

The slide is purely additive and gated on a dynamic flag. To revert: remove the conditional block from `OnboardingPage._buildSlides()`, remove the gate-detection branch from `ReturningUserFlow._advanceFromWelcome`, delete `s075_restricted_settings.dart` and `v3_restricted_settings_step.dart`, drop the i18n keys (or leave them — Slang ignores unused keys), revert the `CapturePermissionsState` field. The Kotlin channel method becomes harmless dead code; can be removed in the same PR or deferred. One-PR revert, no data loss, no migration to undo.

## Dependencies

None. Uses existing `device_info_plus`, `package_info_plus`, the existing `com.bolsio.capture/quirks` channel, and the existing `WidgetsBindingObserver` pattern. No new packages, no new manifest entries, no new permissions.

## Success Criteria

- [ ] On a sideloaded POCO rodin / HyperOS device with the gate active, the new step renders in **every** flow that leads to the listener permission:
  - [ ] First-install onboarding (no Google) — slide between s07 and s08.
  - [ ] First-install onboarding (Google sign-in, Firebase empty) — same slide path.
  - [ ] Returning Google user (Firebase has accounts) — extra step in `ReturningUserFlow` before `_ActivateListenerStep`.
- [ ] On a Play Store install (or any device where the AppOp is `allow`/`default`), the new step does NOT render and flow length is unchanged in all three paths.
- [ ] Tapping the primary CTA deep-links to App Info; returning to Bolsio after enabling "Allow restricted settings" auto-advances within one resume cycle.
- [ ] Tapping "Hacer esto más tarde" advances to the next step without persisting any blocking state.
- [ ] `flutter analyze` clean; `dart run slang` regenerates without collisions.
- [ ] Manual smoke test on POCO rodin confirms the AppOp flips from `ignore` to `allow` and the step auto-advances **in both `OnboardingPage` and `ReturningUserFlow`**.

## Confirmed Decisions

The four open questions from the propose phase were resolved by the user:

1. **Slide filename**: `s075_restricted_settings.dart` — no cascading rename of s08+. Inserted between 07 and 08.
2. **i18n namespace**: nest under `onboarding.restricted_settings.*`.
3. **"Still blocked" hint copy**: minimalista, single-line hint. No troubleshooting block, no per-OEM variants.
4. **Settings -> Auto-import surfacing**: confirmed deferred to a follow-up change. The `CapturePermissionsState` field lands now; the UI row does NOT.

## New Open Questions (surfaced during scope-expansion investigation)

1. **Shared widget vs duplicate**: the proposal recommends a single `v3_restricted_settings_step.dart` consumed by both hosts. Confirm before sdd-spec — alternative is a 95%-duplicated copy embedded directly in `returning_user_flow.dart` (faster to write, but doubles the maintenance footprint when copy/UX evolves).
2. **`ReturningUserFlow` step numbering**: today `_step` is `0|1`. The new gate-fix step would make it `0|1|2` (welcome-back → restricted-settings → activate-listener). Confirm whether the back-pill on the gate-fix step should return to step 0 (welcome-back) like `_ActivateListenerStep` does, or be hidden (no back) since the user just landed there and going back to the welcome hero feels redundant. Recommendation: hide back on the gate-fix step in `ReturningUserFlow`; show back in `OnboardingPage` (which has a global header back-pill anyway).
