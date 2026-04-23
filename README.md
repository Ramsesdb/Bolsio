# Wallex

Fork of [Monekin](https://github.com/enrique-lozano/Monekin) adapted for personal use in Venezuela.
Adds multi-currency (USD/VES) support, BCV/paralelo rate tracking, auto-import from bank notifications,
and AI-assisted transaction entry on top of the original Monekin base.

Licensed under GPL-3.0 (inherited from Monekin).

## Features

- Multi-account, multi-currency tracking (USD + VES with daily-changing rates)
- Per-transaction exchange rate audit (BCV / paralelo / manual)
- Income breakdown by source (tags + categories)
- Budgets and savings goals
- Debt tracking (loans owed / owed to you)
- Recurring transactions
- Reports and statistics with fl_chart
- AI chat assistant with transaction context (Wallex Chat)
- AI hub page for quick financial queries
- Auto-import from bank notification parsing (BDV and configurable profiles)
- Bank statement import (CSV / Excel review flow)
- Receipt OCR import (Google ML Kit, camera or gallery)
- Voice input for transactions
- Hidden mode: PIN + avatar gesture hides savings accounts from the main view
- Biometric lock screen
- Local-first SQLite via Drift ORM; optional Firebase sync (Auth + Firestore + Storage)
- Android (iOS / Web / Windows: partial or planned)

## Stack

Flutter 3.35, Dart >=3.8, Drift ORM (SQLite), fl_chart, slang (i18n), Google ML Kit
(text recognition), Firebase Auth + Firestore + Storage (optional), google_sign_in,
rxdart, file_picker, csv, excel, image_picker.

## Build

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

## Dev notes

**Venezuela seeder** — `lib/core/database/utils/personal_ve_seeders.dart` contains
`PersonalVESeeder`, a one-shot helper that pre-populates accounts, categories, and
tags with Venezuela-specific defaults (BDV, Binance, etc.) and applies seed balances.
It guards against double-run by checking existing account count. Invoke from the
debug page or welcome screen; do not call in automated tests.

**Firebase opt-in** — Firebase is compiled in but sync is user-toggled at runtime via
Settings > Backup. To develop without Firebase, skip replacing `google-services.json`;
the app runs fully offline. For sync testing, supply your own Firebase project config
and enable sync from the Backup settings page
(`lib/app/settings/pages/backup/backup_settings.page.dart`).

**Auto-import profiles** — Bank notification parsing profiles live in
`lib/core/services/auto_import/profiles/`. `BdvNotifProfile` targets Banco de Venezuela
push notifications. New bank profiles implement `BankProfile`. On Xiaomi / HyperOS,
toggle notification listener access off and back on after each `flutter run`.

**trackedSince / Fresh Start** — Accounts have a nullable `trackedSince` field. When
set, statistics exclude transactions before that date, allowing a clean slate without
deleting history.

**Code generation** — Drift and slang require build_runner. Run after any schema or
model change. Generated files (`*.g.dart`) are excluded from the repo; regenerate locally.

## License

GPL-3.0 (inherited from Monekin upstream).
