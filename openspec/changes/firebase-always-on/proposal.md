# Proposal: Firebase Always-On + Google Sign-In First

## Intent

On fresh install, Firebase isn't initialized so Google Sign-In is impossible. Users lose data on every `flutter run` reinstall because there's no cloud backup. The fix: always init Firebase, make "Iniciar con Google" the primary onboarding path, and seed Ramses's real balances on first sign-in.

## Scope

### In Scope
- Always initialize Firebase (remove opt-in flag guard)
- WelcomeScreen: "Iniciar con Google" as primary CTA
- Post-sign-in flow: pull Firebase data → if empty + email matches → seed with balances → push to Firebase
- Email-conditional seed for `ramsesdavidba@gmail.com` with real account balances
- Remove sync toggle from settings (always on when signed in)

### Out of Scope
- Multi-device conflict resolution improvements
- Email/password auth flows (keep as-is, just lower priority in UI)
- Offline-first queue for failed pushes

## Approach

Always call `Firebase.initializeApp()` in `main()`. Remove `firebaseSyncEnabled` flag guard from `FirebaseSyncService.initialize()`. Flip WelcomeScreen buttons. After Google sign-in: pull → check empty → conditional seed → push.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/main.dart:51-63` | Modified | Remove conditional Firebase init |
| `lib/app/auth/welcome_screen.dart` | Modified | Flip CTAs, add post-login pull+seed+push |
| `lib/core/services/firebase_sync_service.dart` | Modified | Remove flag guard in `initialize()` |
| `lib/core/database/utils/personal_ve_seeders.dart` | Modified | Add `seedAllWithBalances()` for known email |
| `lib/app/settings/settings_page.dart` | Modified | Remove sync toggle, show connection status |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Firebase init fails offline | Medium | Existing try/catch, app works offline |
| Double seed race condition | Low | Seeder idempotency guard (account count check) |
| Slow startup from Firebase init | Low | Firebase init is ~200ms, negligible |

## Rollback Plan

Revert 5 files to restore conditional Firebase init and flag-based sync toggle. No data migration needed — Firebase data persists independently.

## Dependencies

- Firebase project configured with Google Sign-In provider enabled (already done)
- `google_sign_in` and `firebase_auth` packages (already in pubspec)

## Success Criteria

- [ ] Fresh install → "Iniciar con Google" works on first screen
- [ ] Sign-in with `ramsesdavidba@gmail.com` → accounts seeded with real balances → pushed to Firebase
- [ ] Reinstall → sign in → data restored from Firebase (non-zero balances)
- [ ] Other email sign-in → accounts seeded with 0 balances
- [ ] Offline startup → app works normally, no crash
