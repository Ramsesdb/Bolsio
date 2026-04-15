# Wallex

Personal finance management app for multi-currency users (USD/VES).

Forked from [Monekin](https://github.com/enrique-lozano/Monekin) (GPL-3.0).

## Features

- Multi-account, multi-currency tracking (USD + VES with daily-changing rates)
- Per-transaction exchange rate audit (BCV / paralelo / manual)
- Income breakdown by source (tags + categories)
- Local-first SQLite + optional Firebase sync
- Android (iOS / Web planned)

## Stack

Flutter, Dart, Drift ORM (SQLite), fl_chart, optional Firebase Auth + Firestore.

## Build

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

## License

GPL-3.0 (inherited from Monekin upstream).
