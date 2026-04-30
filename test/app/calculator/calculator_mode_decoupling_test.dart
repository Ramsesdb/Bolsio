import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 10 task 10.8 — Calculator FX behaviour under non-dual modes.
///
/// Per design.md §8 + Phase 7's verification audit, the calculator is
/// INTENTIONALLY decoupled from `CurrencyDisplayPolicy`. The orchestrator
/// brief frames 10.8 as "Calculator FX test under single_usd, single_bs,
/// single_other(EUR): amount pane behaves consistently without dual
/// assumptions" — the expected behaviour is that the calculator continues
/// to render USD↔VES regardless of the user's mode setting (Phase 7
/// audit, run 8).
///
/// We assert this DECOUPLING at the source level: the calculator feature
/// directory MUST NOT import the policy, the resolver, or any of the four
/// driving setting keys. If a future refactor accidentally couples the
/// calculator to mode (e.g. by importing
/// `CurrencyDisplayPolicyResolver`), this test fails fast — before the
/// regression reaches QA.
///
/// What's covered:
///   - The 6 coupling tokens from Phase 7's audit (`preferredCurrency`,
///     `preferredRateSource`, `currencyMode`, `secondaryCurrency`,
///     `appStateSettings`, `CurrencyDisplayPolicy`) MUST NOT appear in
///     `lib/app/calculator/`.
///   - The calculator's UI-only `RateSource` enum (`lib/app/calculator/
///     models/rate_source.dart`) MUST remain self-contained — distinct
///     from the database `RateSource` enum at
///     `lib/core/services/rate_providers/rate_source.dart`.
///
/// Limitation: a full widget test that renders the calculator under
/// each mode would require a substantial harness (the page boots
/// `DolarApiService`, `CurrencyService`, etc.). This source-level
/// invariant is the maximally strong assertion we can make without that
/// harness — and it directly protects the design §8 contract.
void main() {
  group('Calculator decoupling from CurrencyDisplayPolicy — Task 10.8', () {
    /// The 6 tokens whose presence in the calculator feature would
    /// indicate a coupling to the mode/policy/settings layer. Mirrors
    /// the audit set documented in `apply-progress.md` Run 8.
    const couplingTokens = <String>[
      'preferredCurrency',
      'preferredRateSource',
      'currencyMode',
      'secondaryCurrency',
      'appStateSettings',
      'CurrencyDisplayPolicy',
    ];

    /// Recursively reads every `.dart` file under [dir] into a single map
    /// of `relativePath → contents`. Synchronous I/O is fine — the
    /// calculator directory has ~7 files.
    Map<String, String> readDartFilesUnder(Directory dir) {
      final out = <String, String>{};
      if (!dir.existsSync()) return out;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          out[entity.path] = entity.readAsStringSync();
        }
      }
      return out;
    }

    test(
      'calculator source files contain none of the coupling tokens',
      () {
        // Resolve the calculator directory relative to the test runner's
        // working directory (the project root when invoked via
        // `flutter test`). The Glob search at sub-agent time confirmed
        // 7 .dart files exist under this path.
        final calculatorDir = Directory('lib/app/calculator');
        final files = readDartFilesUnder(calculatorDir);

        expect(
          files,
          isNotEmpty,
          reason: 'Calculator directory must exist and contain .dart files',
        );

        final offenders = <String, List<String>>{};
        files.forEach((path, contents) {
          for (final token in couplingTokens) {
            if (contents.contains(token)) {
              offenders.putIfAbsent(path, () => []).add(token);
            }
          }
        });

        expect(
          offenders,
          isEmpty,
          reason:
              'Calculator MUST remain decoupled from CurrencyDisplayPolicy '
              '(design §8). Found coupling tokens in:\n$offenders',
        );
      },
    );

    test(
      'calculator UI-only RateSource is distinct from the database '
      'RateSource enum',
      () {
        // The calculator has its own `RateSource` enum (UI-only) that
        // intentionally diverges from the database canonical enum. Both
        // files must continue to exist and remain independent.
        final uiRateSource =
            File('lib/app/calculator/models/rate_source.dart');
        final dbRateSource =
            File('lib/core/services/rate_providers/rate_source.dart');

        expect(uiRateSource.existsSync(), isTrue,
            reason: 'Calculator must keep its UI-only RateSource enum.');
        expect(dbRateSource.existsSync(), isTrue,
            reason: 'Database RateSource enum must continue to exist.');

        // The UI-only file must NOT import the DB-side enum (that would
        // collapse the two into one and break design §8's "intentionally
        // independent rate source" rationale).
        final uiContents = uiRateSource.readAsStringSync();
        expect(
          uiContents.contains(
            "import 'package:bolsio/core/services/rate_providers/rate_source.dart'",
          ),
          isFalse,
          reason:
              'Calculator RateSource MUST NOT import the database '
              'RateSource — they are intentionally independent (design §8).',
        );
      },
    );

    test(
      'calculator does not import the rate provider chain',
      () {
        // Per Phase 7 audit: the calculator reads rates only from
        // `DolarApiService`, never from `RateProviderChain`. A future
        // refactor that couples the two would change the calculator's
        // public surface — surface this as a test failure.
        final calculatorDir = Directory('lib/app/calculator');
        final files = readDartFilesUnder(calculatorDir);

        for (final entry in files.entries) {
          expect(
            entry.value.contains('rate_provider_chain.dart'),
            isFalse,
            reason:
                '${entry.key} imports rate_provider_chain — calculator '
                'must remain on DolarApiService per design §8.',
          );
        }
      },
    );

    test(
      'calculator does not consume CurrencyDisplayPolicyResolver',
      () {
        final calculatorDir = Directory('lib/app/calculator');
        final files = readDartFilesUnder(calculatorDir);

        for (final entry in files.entries) {
          expect(
            entry.value.contains('CurrencyDisplayPolicyResolver'),
            isFalse,
            reason:
                '${entry.key} references CurrencyDisplayPolicyResolver — '
                'calculator is intentionally decoupled (design §8 + '
                'Phase 7 audit).',
          );
        }
      },
    );
  });
}
