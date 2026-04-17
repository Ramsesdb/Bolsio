## Exploration: Firebase Always-On + Google Sign-In First

### Current State

Firebase is **opt-in**: `main.dart` checks `SettingKey.firebaseSyncEnabled == '1'` before calling `Firebase.initializeApp()`. On fresh install, Firebase is NOT initialized — the "Conectar con Google" button on WelcomeScreen is disabled because `isFirebaseAvailable` returns false.

**Current flow:**
1. Fresh install → WelcomeScreen
2. "Continuar sin cuenta" (primary CTA) → optional seed → main app (no sync)
3. "Conectar con Google" (secondary, disabled if Firebase not init) → Google Sign-In → enable sync → main app

**Problem:** Since Firebase isn't initialized on fresh install, Google Sign-In is impossible on first run. The user must first continue without account, manually enable sync in settings, restart the app, then sign in. Data entered before sign-in isn't synced unless manually pushed.

### Affected Areas

- `lib/main.dart` — Firebase init logic (lines 51-63): remove conditional, always init
- `lib/app/auth/welcome_screen.dart` — Flip CTAs: Google Sign-In becomes primary; "Continuar sin cuenta" becomes secondary
- `lib/core/services/firebase_sync_service.dart` — Remove sync flag guard in `initialize()`; add email-conditional seed logic
- `lib/core/database/utils/personal_ve_seeders.dart` — Add `seedAllWithBalances()` variant for known email
- `lib/app/settings/settings_page.dart` — Remove sync toggle (always on); rename UI references

### Approaches

1. **Always-init Firebase + flip WelcomeScreen CTAs**
   - Firebase.initializeApp() always runs in main.dart (no flag check)
   - WelcomeScreen: "Iniciar con Google" = primary FilledButton; "Continuar sin cuenta" = secondary OutlinedButton
   - After Google sign-in: check Firebase for data → pull if exists → seed if empty
   - If email == ramsesdavidba@gmail.com AND Firebase empty → seed with real balances
   - After seed → pushAllData() to Firebase
   - Pros: Simple, minimal code change, solves all user problems
   - Cons: Firebase always initializes even offline (handled by try/catch)
   - Effort: Medium

2. **Lazy Firebase init on sign-in attempt**
   - Keep Firebase uninit on startup, but init when user taps "Iniciar con Google"
   - Pros: No wasted init if user goes offline-only
   - Cons: More complex flow, sign-in button needs loading state for Firebase init
   - Effort: Medium-High

### Recommendation

**Approach 1**: Always-init Firebase. The app is personal — Firebase is always wanted. The try/catch already handles offline gracefully. Changes are surgical:

1. `main.dart`: Remove `if (syncEnabled)` guard → always call `Firebase.initializeApp()` + `FirebaseSyncService.instance.initialize()`
2. `welcome_screen.dart`: Swap button hierarchy. After Google sign-in success, add: pull → check if empty → conditional seed → push
3. `personal_ve_seeders.dart`: Add static map of Ramses's balances + `seedAllWithBalances()` method
4. `firebase_sync_service.dart`: Remove flag check in `initialize()`, always init if Firebase core is ready
5. `settings_page.dart`: Remove sync toggle, always show as "Conectado con Google" when signed in

### Risks

- Firebase init failure on first cold start (offline): mitigated by existing try/catch, app works offline
- Double seed if sign-in races with local seed: mitigated by idempotency guard in seeder
- Existing users with sync disabled: on next app start Firebase will init but sync won't push unless user explicitly signs in

### Ready for Proposal

Yes — the scope is clear, files are identified, approach is straightforward. Proceed to proposal.
