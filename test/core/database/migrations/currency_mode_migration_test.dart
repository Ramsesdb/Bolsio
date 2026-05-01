import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/core/models/currency/currency_mode.dart';
import 'package:nitido/core/services/rate_providers/rate_source.dart';

/// Phase 10 task 10.1 + 10.2 — migration surrogate tests.
///
/// The actual migration logic lives in `assets/sql/migrations/v28.sql` as
/// raw SQL, executed against a real Drift database at app cold-start.
/// Booting an in-memory `AppDB` instance with the migration runner here
/// would require a substantial harness (path_provider mock, SQLite native
/// libs, asset bundle stubbing) that this codebase does NOT currently
/// expose — see `test/hidden_mode_service_test.dart` for the documented
/// reasoning around skipping the Drift boot in unit tests.
///
/// Per the orchestrator brief ("If a Drift in-memory migration test is too
/// complex without project-specific helpers, document why and write a
/// smaller surrogate"), this file ports the v28.sql heuristic to pure Dart
/// and exercises the same decision table. Test failures here mean the
/// SQL must change; conversely, if the SQL changes, this test must be
/// updated to mirror it. The heuristic is anchored against `design.md §2`
/// + the inline doc on `assets/sql/migrations/v28.sql` lines 132-141.
///
/// What's covered:
///   - Task 10.1: 3 beta heuristic scenarios + the "no preferred currency
///     at all" case + idempotency.
///   - Task 10.2: CHECK widening + lowercase one-shot — pure-Dart port of
///     the `CASE WHEN exchangeRateSource = 'auto' THEN 'auto_frankfurter'`
///     remap, plus the lowercase normalization for `exchangeRates.source`.
///     The `RateSource.fromDb` parser already enforces this contract on the
///     read side; here we verify the write-side mapping.
void main() {
  group('Migration heuristic (v28.sql) — Task 10.1', () {
    /// Dart port of the v28.sql `currencyMode` CASE expression.
    /// Matches the SQL verbatim (see migration file lines 144-155).
    String resolveCurrencyMode({
      required String? preferredCurrency,
      required String? preferredRateSource,
    }) {
      // SQL: WHEN EXISTS (... preferredRateSource) THEN 'dual'
      if (preferredRateSource != null) return 'dual';
      // SQL: WHEN preferredCurrency = 'USD' THEN 'single_usd'
      if (preferredCurrency == 'USD') return 'single_usd';
      // SQL: WHEN preferredCurrency = 'VES' THEN 'single_bs'
      if (preferredCurrency == 'VES') return 'single_bs';
      // SQL: WHEN preferredCurrency IS NOT NULL THEN 'single_other'
      if (preferredCurrency != null) return 'single_other';
      // SQL: ELSE 'dual'
      return 'dual';
    }

    /// Dart port of the v28.sql `secondaryCurrency` CASE expression.
    /// Matches the SQL verbatim (see migration file lines 157-165).
    String? resolveSecondaryCurrency({
      required String? preferredCurrency,
      required String? preferredRateSource,
    }) {
      if (preferredRateSource != null) return 'VES';
      if (preferredCurrency == null) return 'VES';
      return null;
    }

    test(
      'Beta user A: preferredCurrency=USD + preferredRateSource=bcv '
      '→ dual + VES (intended dual user)',
      () {
        // The exact spec scenario from design.md §2: a returning beta user
        // who picked the legacy "USD with BCV rate source" actually meant
        // dual mode all along (the legacy collapse hid this).
        final mode = resolveCurrencyMode(
          preferredCurrency: 'USD',
          preferredRateSource: 'bcv',
        );
        final secondary = resolveSecondaryCurrency(
          preferredCurrency: 'USD',
          preferredRateSource: 'bcv',
        );
        expect(mode, 'dual');
        expect(secondary, 'VES');
        // Sanity check: the result parses round-trip via the Phase 1
        // tolerant parsers.
        expect(CurrencyMode.fromDb(mode), CurrencyMode.dual);
      },
    );

    test(
      'Beta user B: preferredCurrency=VES + no preferredRateSource '
      '→ single_bs',
      () {
        final mode = resolveCurrencyMode(
          preferredCurrency: 'VES',
          preferredRateSource: null,
        );
        final secondary = resolveSecondaryCurrency(
          preferredCurrency: 'VES',
          preferredRateSource: null,
        );
        expect(mode, 'single_bs');
        expect(
          secondary,
          isNull,
          reason: 'Single modes MUST NOT seed a secondary (preserved on '
              'subsequent Dual switch instead).',
        );
      },
    );

    test(
      'Beta user C: preferredCurrency=USD + no preferredRateSource '
      '→ single_usd',
      () {
        final mode = resolveCurrencyMode(
          preferredCurrency: 'USD',
          preferredRateSource: null,
        );
        final secondary = resolveSecondaryCurrency(
          preferredCurrency: 'USD',
          preferredRateSource: null,
        );
        expect(mode, 'single_usd');
        expect(secondary, isNull);
      },
    );

    test(
      'preferredCurrency=EUR + no preferredRateSource → single_other',
      () {
        final mode = resolveCurrencyMode(
          preferredCurrency: 'EUR',
          preferredRateSource: null,
        );
        final secondary = resolveSecondaryCurrency(
          preferredCurrency: 'EUR',
          preferredRateSource: null,
        );
        expect(mode, 'single_other');
        expect(secondary, isNull);
      },
    );

    test(
      'No keys at all (fresh install OR pre-onboarding) → dual + VES',
      () {
        final mode = resolveCurrencyMode(
          preferredCurrency: null,
          preferredRateSource: null,
        );
        final secondary = resolveSecondaryCurrency(
          preferredCurrency: null,
          preferredRateSource: null,
        );
        expect(mode, 'dual');
        expect(secondary, 'VES');
      },
    );

    test(
      'Idempotency: re-running the heuristic on already-seeded rows is '
      'a no-op (INSERT OR IGNORE in SQL)',
      () {
        // The SQL uses `INSERT OR IGNORE` keyed on `settingKey` (the PK),
        // so a re-run never overwrites an existing row. We verify the
        // logic produces a stable answer for the same input — running the
        // heuristic twice yields identical results.
        final inputs = <({String? pref, String? rate})>[
          (pref: 'USD', rate: 'bcv'),
          (pref: 'VES', rate: null),
          (pref: 'USD', rate: null),
          (pref: 'EUR', rate: null),
          (pref: null, rate: null),
        ];
        for (final input in inputs) {
          final mode1 = resolveCurrencyMode(
            preferredCurrency: input.pref,
            preferredRateSource: input.rate,
          );
          final mode2 = resolveCurrencyMode(
            preferredCurrency: input.pref,
            preferredRateSource: input.rate,
          );
          final sec1 = resolveSecondaryCurrency(
            preferredCurrency: input.pref,
            preferredRateSource: input.rate,
          );
          final sec2 = resolveSecondaryCurrency(
            preferredCurrency: input.pref,
            preferredRateSource: input.rate,
          );
          expect(mode1, mode2);
          expect(sec1, sec2);
        }
      },
    );
  });

  group(
    'Migration: CHECK widening + lowercase one-shot — Task 10.2',
    () {
      /// Dart port of the v28.sql `exchangeRateSource` CASE expression.
      /// Matches the SQL verbatim (see migration file lines 103-107).
      String? remapTransactionSource(String? source) {
        if (source == null) return null;
        final lower = source.toLowerCase();
        if (lower == 'auto') return 'auto_frankfurter';
        return lower;
      }

      /// Dart port of the v28.sql `UPDATE exchangeRates SET source = LOWER(source)`
      /// statement (line 130).
      String? lowercaseExchangeRateSource(String? source) {
        return source?.toLowerCase();
      }

      test('legacy "auto" → "auto_frankfurter" on transactions table', () {
        expect(remapTransactionSource('auto'), 'auto_frankfurter');
        expect(remapTransactionSource('AUTO'), 'auto_frankfurter');
        expect(remapTransactionSource('Auto'), 'auto_frankfurter');
      });

      test('uppercase canonical sources lowercased on transactions table',
          () {
        expect(remapTransactionSource('BCV'), 'bcv');
        expect(remapTransactionSource('Paralelo'), 'paralelo');
        expect(remapTransactionSource('MANUAL'), 'manual');
      });

      test(
        'already-lowercase sources untouched (idempotency)',
        () {
          expect(remapTransactionSource('bcv'), 'bcv');
          expect(remapTransactionSource('paralelo'), 'paralelo');
          expect(remapTransactionSource('manual'), 'manual');
          expect(
            remapTransactionSource('auto_frankfurter'),
            'auto_frankfurter',
          );
        },
      );

      test('NULL source preserved on transactions table', () {
        expect(remapTransactionSource(null), isNull);
      });

      test(
        'all post-migration values pass the new CHECK constraint set',
        () {
          // Post-migration the CHECK is widened to
          // ('bcv','paralelo','manual','auto_frankfurter'). Every output
          // of the remap must land in this set.
          const allowedSet = {
            'bcv',
            'paralelo',
            'manual',
            'auto_frankfurter',
          };
          for (final input in <String?>[
            'auto',
            'AUTO',
            'BCV',
            'Paralelo',
            'manual',
            'auto_frankfurter',
            null,
          ]) {
            final out = remapTransactionSource(input);
            if (out != null) {
              expect(
                allowedSet.contains(out),
                isTrue,
                reason: 'remap("$input") = "$out" — must be in CHECK set',
              );
            }
          }
        },
      );

      test(
        'exchangeRates.source: lowercase one-shot is idempotent',
        () {
          expect(lowercaseExchangeRateSource('AUTO'), 'auto');
          expect(lowercaseExchangeRateSource('Bcv'), 'bcv');
          expect(lowercaseExchangeRateSource('paralelo'), 'paralelo');
          expect(lowercaseExchangeRateSource(null), isNull);
          // Re-running on already-lowercase rows is a no-op.
          expect(
            lowercaseExchangeRateSource(lowercaseExchangeRateSource('AUTO')),
            'auto',
          );
        },
      );

      test(
        'every post-migration exchangeRates.source value parses via '
        'RateSource.fromDb',
        () {
          // After v28 the exchangeRates.source column is canonical lowercase.
          // The Phase 1 tolerant parser MUST round-trip every legal value.
          for (final raw in <String?>[
            'bcv',
            'paralelo',
            'manual',
            'auto', // legacy alias — fromDb maps to autoFrankfurter
            'auto_frankfurter',
            null,
          ]) {
            final parsed = RateSource.fromDb(raw);
            // The parser must never throw and must produce one of the four
            // enum values.
            expect(RateSource.values.contains(parsed), isTrue);
          }
        },
      );
    },
  );
}
