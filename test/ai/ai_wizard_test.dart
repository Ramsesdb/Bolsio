import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nitido/app/settings/pages/ai/wizard/steps/s1_welcome.step.dart';
import 'package:nitido/app/settings/pages/ai/wizard/steps/s2_choose_provider.step.dart';
import 'package:nitido/app/settings/pages/ai/wizard/steps/s4_paste_key.step.dart';
import 'package:nitido/app/settings/pages/ai/wizard/widgets/provider_card.dart';
import 'package:nitido/core/services/ai/ai_provider_type.dart';

/// Widget tests for the AI setup wizard.
///
/// We exercise the steps in isolation rather than mounting the whole
/// `AiWizardPage` because the host depends on `AiCredentialsStore` (which
/// in turn talks to `flutter_secure_storage` and Drift) — those need
/// platform channels that are not trivial to stub in a pure widget test.
/// The per-step tests cover the public contract the host depends on:
/// - step 1 emits `onStart` / `onLater`
/// - step 2 disables the primary CTA until a provider is selected and
///   emits `onSelect` / `onContinue` / `onUseExisting`
/// - step 4 validates the API key heuristic + auto-paste banner
void main() {
  // The clipboard channel is hit by S4PasteKeyStep on initState. Stub it
  // to a known value so we can assert on the auto-detect banner.
  void stubClipboard(String? value) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return value == null ? null : <String, dynamic>{'text': value};
      }
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('looksLikeKeyFor', () {
    test('detects OpenAI keys (sk- prefix, length > 20)', () {
      expect(
        looksLikeKeyFor(
          AiProviderType.openai,
          'sk-${'A' * 30}',
        ),
        isTrue,
      );
      expect(looksLikeKeyFor(AiProviderType.openai, 'sk-tooshort'), isFalse);
      expect(
        looksLikeKeyFor(AiProviderType.openai, 'no-prefix-${'A' * 30}'),
        isFalse,
      );
    });

    test('detects Anthropic keys (sk-ant- prefix)', () {
      expect(
        looksLikeKeyFor(AiProviderType.anthropic, 'sk-ant-${'B' * 30}'),
        isTrue,
      );
      expect(
        looksLikeKeyFor(AiProviderType.anthropic, 'sk-${'B' * 30}'),
        isFalse,
      );
    });

    test('detects Nexus keys (sk- or tk_ prefix)', () {
      expect(
        looksLikeKeyFor(AiProviderType.nexus, 'sk-${'C' * 30}'),
        isTrue,
      );
      expect(
        looksLikeKeyFor(AiProviderType.nexus, 'tk_${'D' * 30}'),
        isTrue,
      );
      expect(
        looksLikeKeyFor(AiProviderType.nexus, 'AIza${'D' * 30}'),
        isFalse,
      );
    });

    test('rejects strings with whitespace', () {
      expect(
        looksLikeKeyFor(AiProviderType.openai, 'sk-${'A' * 30} extra'),
        isFalse,
      );
    });

    test('Gemini accepts long alphanumeric strings', () {
      expect(
        looksLikeKeyFor(
          AiProviderType.gemini,
          'AIzaSyA1234567890abcdefghijklmnop',
        ),
        isTrue,
      );
      expect(looksLikeKeyFor(AiProviderType.gemini, 'short'), isFalse);
    });
  });

  group('S1WelcomeStep', () {
    testWidgets('renders title and emits onStart', (tester) async {
      bool started = false;
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: S1WelcomeStep(
            currentStep: 0,
            totalSteps: 6,
            onStart: () => started = true,
            onLater: () => dismissed = true,
          ),
        ),
      );
      expect(find.textContaining('Configurá'), findsOneWidget);
      // Two CTAs visible.
      expect(find.text('Empezar'), findsOneWidget);
      expect(find.text('Después'), findsOneWidget);
      await tester.tap(find.text('Empezar'));
      expect(started, isTrue);
      expect(dismissed, isFalse);
    });

    testWidgets('emits onLater when "Después" is tapped', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: S1WelcomeStep(
            currentStep: 0,
            totalSteps: 6,
            onStart: () {},
            onLater: () => dismissed = true,
          ),
        ),
      );
      await tester.tap(find.text('Después'));
      expect(dismissed, isTrue);
    });
  });

  group('S2ChooseProviderStep', () {
    testWidgets('disables Continuar until a provider is picked',
        (tester) async {
      AiProviderType? chosen;
      bool continued = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return S2ChooseProviderStep(
                currentStep: 1,
                totalSteps: 6,
                selected: chosen,
                configuredProviders: const {},
                onSelect: (p) => setState(() => chosen = p),
                onContinue: () => continued = true,
                onBack: () {},
                onUseExisting: () {},
              );
            },
          ),
        ),
      );

      // Continue is rendered but disabled.
      final continueFinder = find.text('Continuar');
      expect(continueFinder, findsOneWidget);
      await tester.tap(continueFinder);
      await tester.pump();
      expect(continued, isFalse);

      // Select OpenAI.
      await tester.tap(find.byType(WizardProviderCard).at(1));
      await tester.pump();
      expect(chosen, AiProviderType.openai);

      // Continue now fires.
      await tester.tap(continueFinder);
      await tester.pump();
      expect(continued, isTrue);
    });

    testWidgets('shows "Usar la guardada" shortcut for configured providers',
        (tester) async {
      bool used = false;
      await tester.pumpWidget(
        MaterialApp(
          home: S2ChooseProviderStep(
            currentStep: 1,
            totalSteps: 6,
            selected: AiProviderType.openai,
            configuredProviders: const {AiProviderType.openai},
            onSelect: (_) {},
            onContinue: () {},
            onBack: () {},
            onUseExisting: () => used = true,
          ),
        ),
      );

      expect(find.text('Usar la guardada'), findsOneWidget);
      await tester.tap(find.text('Usar la guardada'));
      expect(used, isTrue);
    });
  });

  group('S4PasteKeyStep', () {
    testWidgets('disables Continuar when input is empty', (tester) async {
      stubClipboard(null);
      bool submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: S4PasteKeyStep(
            currentStep: 3,
            totalSteps: 6,
            provider: AiProviderType.openai,
            initialApiKey: null,
            initialModel: null,
            initialBaseUrl: null,
            onSubmit: ({required apiKey, model, baseUrl}) {
              submitted = true;
            },
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(submitted, isFalse, reason: 'empty key must not submit');
    });

    testWidgets('auto-detects clipboard key and shows banner', (tester) async {
      stubClipboard('sk-${'X' * 30}');

      await tester.pumpWidget(
        MaterialApp(
          home: S4PasteKeyStep(
            currentStep: 3,
            totalSteps: 6,
            provider: AiProviderType.openai,
            initialApiKey: null,
            initialModel: null,
            initialBaseUrl: null,
            onSubmit: ({required apiKey, model, baseUrl}) {},
            onBack: () {},
          ),
        ),
      );
      // Allow the postFrameCallback + clipboard future to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.textContaining('Detectamos una key'),
        findsOneWidget,
      );
    });

    testWidgets('emits onSubmit with the typed key', (tester) async {
      stubClipboard(null);
      String? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: S4PasteKeyStep(
            currentStep: 3,
            totalSteps: 6,
            provider: AiProviderType.openai,
            initialApiKey: null,
            initialModel: null,
            initialBaseUrl: null,
            onSubmit: ({required apiKey, model, baseUrl}) {
              captured = apiKey;
            },
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'sk-typedkey');
      await tester.pump();

      await tester.tap(find.text('Continuar'));
      await tester.pump();
      expect(captured, 'sk-typedkey');
    });
  });
}
