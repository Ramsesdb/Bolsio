import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';
import 'package:nitido/core/models/currency/currency_display_policy.dart';
import 'package:nitido/core/models/currency/currency_display_policy_resolver.dart';

/// Phase 10 task 10.4 — `CurrencyDisplayPolicyResolver` stream contract.
///
/// The pure resolution table is exhaustively covered by
/// `currency_display_policy_test.dart` (26 tests, Phase 2). This file
/// pins the stream-composition contract: the resolver MUST emit a new
/// policy on any of the three driving settings changing, AND `.distinct()`
/// MUST suppress equal policies.
///
/// Strategy: rather than booting a real `UserSettingService` (which
/// requires `AppDB.instance`, path_provider, asset bundles), we replay the
/// resolver's `Rx.combineLatest3 + .distinct()` composition directly with
/// `BehaviorSubject` driving streams. This exercises the SAME stream
/// contract — `Rx.combineLatest3` + `.distinct()` operating on the output
/// of `CurrencyDisplayPolicyResolver.buildPolicy(...)` — without paying
/// the AppDB boot cost. If the resolver ever switches to a different
/// stream operator (e.g. `Rx.combineLatest4` after a 4th driving key
/// lands), this test must be updated to mirror it.
void main() {
  group('CurrencyDisplayPolicyResolver stream contract — Task 10.4', () {
    /// Replays the resolver's stream composition (matches
    /// `CurrencyDisplayPolicyResolver.watch()` line-for-line).
    Stream<CurrencyDisplayPolicy> buildResolverStream({
      required Stream<String?> preferredCurrency,
      required Stream<String?> currencyMode,
      required Stream<String?> secondaryCurrency,
    }) {
      return Rx.combineLatest3<String?, String?, String?, CurrencyDisplayPolicy>(
        preferredCurrency,
        currencyMode,
        secondaryCurrency,
        (pref, mode, sec) =>
            CurrencyDisplayPolicyResolver.buildPolicy(
          preferredCurrency: pref,
          currencyMode: mode,
          secondaryCurrency: sec,
        ),
      ).distinct();
    }

    test(
      'emits initial policy from the first combined emission',
      () async {
        final pref = BehaviorSubject<String?>.seeded('USD');
        final mode = BehaviorSubject<String?>.seeded('dual');
        final sec = BehaviorSubject<String?>.seeded('VES');

        final stream$ = buildResolverStream(
          preferredCurrency: pref.stream,
          currencyMode: mode.stream,
          secondaryCurrency: sec.stream,
        );

        final first = await stream$.first;
        expect(first, const DualMode(primary: 'USD', secondary: 'VES'));

        await pref.close();
        await mode.close();
        await sec.close();
      },
    );

    test(
      're-emits when currencyMode changes (dual → single_usd)',
      () async {
        final pref = BehaviorSubject<String?>.seeded('USD');
        final mode = BehaviorSubject<String?>.seeded('dual');
        final sec = BehaviorSubject<String?>.seeded('VES');

        final stream$ = buildResolverStream(
          preferredCurrency: pref.stream,
          currencyMode: mode.stream,
          secondaryCurrency: sec.stream,
        );

        final emitted = <CurrencyDisplayPolicy>[];
        final sub = stream$.listen(emitted.add);

        // Allow the initial combineLatest emission.
        await Future<void>.delayed(Duration.zero);

        // Mode change: dual → single_usd.
        mode.add('single_usd');
        await Future<void>.delayed(Duration.zero);

        expect(emitted, [
          const DualMode(primary: 'USD', secondary: 'VES'),
          const SingleMode(code: 'USD'),
        ]);

        await sub.cancel();
        await pref.close();
        await mode.close();
        await sec.close();
      },
    );

    test(
      're-emits when secondaryCurrency changes (VES → ARS) within dual',
      () async {
        final pref = BehaviorSubject<String?>.seeded('EUR');
        final mode = BehaviorSubject<String?>.seeded('dual');
        final sec = BehaviorSubject<String?>.seeded('VES');

        final stream$ = buildResolverStream(
          preferredCurrency: pref.stream,
          currencyMode: mode.stream,
          secondaryCurrency: sec.stream,
        );

        final emitted = <CurrencyDisplayPolicy>[];
        final sub = stream$.listen(emitted.add);
        await Future<void>.delayed(Duration.zero);

        sec.add('ARS');
        await Future<void>.delayed(Duration.zero);

        expect(emitted, [
          const DualMode(primary: 'EUR', secondary: 'VES'),
          const DualMode(primary: 'EUR', secondary: 'ARS'),
        ]);

        await sub.cancel();
        await pref.close();
        await mode.close();
        await sec.close();
      },
    );

    test(
      '.distinct() suppresses duplicate policies across redundant emissions',
      () async {
        // Verifies the spec scenario "Cliente antiguo sin las claves" +
        // the resolver's `.distinct()` guarantee (design.md §3): two
        // identical resolved policies in a row MUST NOT trigger a re-emit.
        final pref = BehaviorSubject<String?>.seeded('USD');
        final mode = BehaviorSubject<String?>.seeded('dual');
        final sec = BehaviorSubject<String?>.seeded('VES');

        final stream$ = buildResolverStream(
          preferredCurrency: pref.stream,
          currencyMode: mode.stream,
          secondaryCurrency: sec.stream,
        );

        final emitted = <CurrencyDisplayPolicy>[];
        final sub = stream$.listen(emitted.add);
        await Future<void>.delayed(Duration.zero);

        // Re-emit the same value on each underlying subject. `.distinct()`
        // must suppress every redundant downstream emission.
        pref.add('USD');
        mode.add('dual');
        sec.add('VES');
        await Future<void>.delayed(Duration.zero);

        expect(
          emitted,
          [const DualMode(primary: 'USD', secondary: 'VES')],
          reason:
              'Three redundant upstream emissions MUST collapse to a '
              'single downstream emit.',
        );

        await sub.cancel();
        await pref.close();
        await mode.close();
        await sec.close();
      },
    );

    test(
      'unknown currencyMode value falls back to dual(USD, VES) without '
      'error (forward-compat)',
      () async {
        // A blob from a future client emits a mode value this binary
        // does not know. The resolver must downgrade gracefully — no
        // exception, just a safe `dual(USD,VES)` policy.
        final pref = BehaviorSubject<String?>.seeded(null);
        final mode = BehaviorSubject<String?>.seeded(
          'something_from_a_future_client',
        );
        final sec = BehaviorSubject<String?>.seeded(null);

        final stream$ = buildResolverStream(
          preferredCurrency: pref.stream,
          currencyMode: mode.stream,
          secondaryCurrency: sec.stream,
        );

        final first = await stream$.first;
        expect(first, const DualMode(primary: 'USD', secondary: 'VES'));

        await pref.close();
        await mode.close();
        await sec.close();
      },
    );

    test(
      'mode toggles single_usd → single_bs → single_other emit three '
      'distinct policies',
      () async {
        final pref = BehaviorSubject<String?>.seeded('EUR');
        final mode = BehaviorSubject<String?>.seeded('single_usd');
        final sec = BehaviorSubject<String?>.seeded(null);

        final stream$ = buildResolverStream(
          preferredCurrency: pref.stream,
          currencyMode: mode.stream,
          secondaryCurrency: sec.stream,
        );

        final emitted = <CurrencyDisplayPolicy>[];
        final sub = stream$.listen(emitted.add);
        await Future<void>.delayed(Duration.zero);

        mode.add('single_bs');
        await Future<void>.delayed(Duration.zero);

        mode.add('single_other');
        await Future<void>.delayed(Duration.zero);

        expect(emitted, [
          const SingleMode(code: 'USD'),
          const SingleMode(code: 'VES'),
          const SingleMode(code: 'EUR'),
        ]);

        await sub.cancel();
        await pref.close();
        await mode.close();
        await sec.close();
      },
    );
  });
}
