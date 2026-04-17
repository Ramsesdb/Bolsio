# Tasks: Firebase Always-On + Google Sign-In First

## Phase 1: Firebase Init (foundation — no UI changes yet)

- [x] 1.1 `lib/main.dart`: Remove `if (syncEnabled)` guard around `Firebase.initializeApp()` + `FirebaseSyncService.instance.initialize()`. Always call both inside try/catch.
- [x] 1.2 `lib/core/services/firebase_sync_service.dart`: In `initialize()`, remove the `syncFlag != '1'` early-return check. Keep `_isFirebaseCoreReady` check.
- [x] 1.3 `lib/main.dart`: Remove the `firebaseSyncEnabled` setting read and the `syncEnabled` variable (lines 52-63). Keep the try/catch wrapper.

## Phase 2: Email-Conditional Seed

- [x] 2.1 `lib/core/database/utils/personal_ve_seeders.dart`: Add `static const _ramseBalances` map with real balances.
- [x] 2.2 `personal_ve_seeders.dart`: Add `static Future<void> seedAllWithBalances()` — calls `seedAll()` then updates iniValue for each entry in `_ramseBalances`.

## Phase 3: WelcomeScreen Flow

- [x] 3.1 `lib/app/auth/welcome_screen.dart`: Swap button hierarchy — "Iniciar con Google" becomes `FilledButton` (primary), "Continuar sin cuenta" becomes `OutlinedButton` (secondary).
- [x] 3.2 `welcome_screen.dart`: In `_signInWithGoogle()`, after sign-in success: call `FirebaseSyncService.instance.pullAllData()`.
- [x] 3.3 `welcome_screen.dart`: After pull, check if accounts exist locally. If 0 accounts: check email. If `ramsesdavidba@gmail.com` → `seedAllWithBalances()`. Else → `seedAll()`.
- [x] 3.4 `welcome_screen.dart`: After seed, call `FirebaseSyncService.instance.pushAllData()` to persist to Firebase.

## Phase 4: Settings Cleanup

- [x] 4.1 `lib/app/settings/settings_page.dart`: Remove sync toggle. Replace with read-only `ListTile` showing "Conectado como {email}" or "Sin cuenta".
- [x] 4.2 `settings_page.dart`: Remove `_syncEnabled` state variable and `_onSyncToggled` method.

## Phase 5: Verify on Device

- [ ] 5.1 Build + deploy via `flutter run`. Fresh install → tap "Iniciar con Google" → sign in with `ramsesdavidba@gmail.com` → verify accounts appear with real balances.
- [ ] 5.2 Force-stop app → relaunch → verify balances persist (local DB).
- [ ] 5.3 Reinstall app (`flutter run` again) → sign in → verify data restored from Firebase (non-zero balances).
- [ ] 5.4 Test offline: airplane mode → launch app → verify no crash, app works with local data.
