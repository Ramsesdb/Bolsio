import 'package:flutter/material.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/steps/s1_welcome.step.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/steps/s2_choose_provider.step.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/steps/s3_get_key.step.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/steps/s4_paste_key.step.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/steps/s5_testing.step.dart';
import 'package:bolsio/app/settings/pages/ai/wizard/steps/s6_done.step.dart';
import 'package:bolsio/core/services/ai/ai_credentials.dart';
import 'package:bolsio/core/services/ai/ai_credentials_store.dart';
import 'package:bolsio/core/services/ai/ai_provider_type.dart';
import 'package:bolsio/core/services/ai/ai_service.dart';

/// Host of the AI setup wizard — owns the [PageController], the provider
/// selection state, the in-flight credentials, and the "where do we go
/// next" routing between the 6 steps.
///
/// Persistence semantics (per spec):
///   - We only call [AiCredentialsStore.saveCredentials] / `setActiveProvider`
///     AFTER the user clears step 5 (connection test). If they bail before
///     that, no invalid credentials end up on disk.
///   - When the user picks an already-configured provider in step 2 and
///     taps "Usar la guardada", the wizard skips step 3 + step 4 and runs
///     the test directly against the stored credentials. On success we
///     just flip `setActiveProvider` (the credential row is already there).
class AiWizardPage extends StatefulWidget {
  const AiWizardPage({super.key});

  @override
  State<AiWizardPage> createState() => _AiWizardPageState();
}

class _AiWizardPageState extends State<AiWizardPage> {
  static const int _totalSteps = 6;

  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // ── Selection state ──────────────────────────────────────────────────
  AiProviderType? _selectedProvider;
  final Set<AiProviderType> _configuredProviders = <AiProviderType>{};

  /// Credentials currently being entered/tested. Built in step 4, consumed
  /// in step 5, and persisted on success right before step 6 mounts.
  AiCredentials? _pendingCredentials;

  /// Resolved model id used by the success summary in step 6. Populated
  /// after [AiService.resolveEffectiveModel] runs (step 5 → step 6).
  String? _effectiveModel;

  @override
  void initState() {
    super.initState();
    _loadConfiguredProviders();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadConfiguredProviders() async {
    final list =
        await AiCredentialsStore.instance.listConfiguredProviders();
    if (!mounted) return;
    setState(() {
      _configuredProviders
        ..clear()
        ..addAll(list);
    });
  }

  // ── Navigation primitives ────────────────────────────────────────────

  void _goTo(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  void _next() => _goTo(_currentIndex + 1);
  void _previous() {
    if (_currentIndex <= 0) return;
    _goTo(_currentIndex - 1);
  }

  /// Pop the wizard route entirely. Used for the welcome "Después" CTA
  /// and for the final "Empezar a usar bolsio" CTA.
  void _exitWizard() {
    Navigator.of(context).maybePop();
  }

  // ── Step transition handlers ─────────────────────────────────────────

  void _onProviderSelected(AiProviderType provider) {
    setState(() => _selectedProvider = provider);
  }

  /// User picked a provider that already had credentials and tapped
  /// "Usar la guardada". We skip steps 3 + 4 and load the stored creds
  /// straight into the test step.
  Future<void> _onUseExistingCredentials() async {
    final provider = _selectedProvider;
    if (provider == null) return;
    final stored = await AiCredentialsStore.instance.loadCredentials(provider);
    if (stored == null) {
      // Race: badge said "configured" but the row vanished. Fall through
      // to the normal flow so the user can re-paste.
      _next();
      return;
    }
    setState(() => _pendingCredentials = stored);
    // Jump to step 5 (index 4). Steps 3 + 4 stay mounted in the PageView
    // but are not visited.
    _goTo(4);
  }

  void _onPasteKeySubmitted({
    required String apiKey,
    String? model,
    String? baseUrl,
  }) {
    final provider = _selectedProvider;
    if (provider == null) return;
    setState(() {
      _pendingCredentials = AiCredentials(
        providerType: provider,
        apiKey: apiKey,
        model: model,
        baseUrl: baseUrl,
      );
    });
    _next(); // step 5
  }

  Future<void> _onTestSucceeded() async {
    final creds = _pendingCredentials;
    if (creds == null) return;
    // Persist + activate the credentials. We do this only AFTER a green
    // test so partial wizard exits never leave invalid keys on disk.
    await AiCredentialsStore.instance.saveCredentials(creds);
    await AiCredentialsStore.instance.setActiveProvider(creds.providerType);
    if (!mounted) return;
    setState(() {
      _effectiveModel = AiService.instance.resolveEffectiveModel(creds);
      _configuredProviders.add(creds.providerType);
    });
    _goTo(5); // step 6
  }

  void _onEditKeyAfterFailure() {
    // Send the user back to step 4 with the credentials they typed
    // pre-filled (so they don't have to re-paste the whole thing).
    _goTo(3);
  }

  void _onConfigureAnother() {
    setState(() {
      _selectedProvider = null;
      _pendingCredentials = null;
      _effectiveModel = null;
    });
    _goTo(1); // back to step 2 (chooser)
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The wizard's internal "back" handlers always animate the
      // PageController. Allow the system back button to actually pop the
      // route only when we're on the first step or step 6 (no further
      // back-step makes sense). On other steps we intercept and rewind.
      canPop: _currentIndex == 0 || _currentIndex == 5,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex > 0 && _currentIndex != 5) {
          _previous();
        }
      },
      child: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _totalSteps,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) => _buildStep(i),
      ),
    );
  }

  Widget _buildStep(int index) {
    switch (index) {
      case 0:
        return S1WelcomeStep(
          currentStep: 0,
          totalSteps: _totalSteps,
          onStart: _next,
          onLater: _exitWizard,
        );
      case 1:
        return S2ChooseProviderStep(
          currentStep: 1,
          totalSteps: _totalSteps,
          selected: _selectedProvider,
          configuredProviders: _configuredProviders,
          onSelect: _onProviderSelected,
          onContinue: _next,
          onBack: _previous,
          onUseExisting: _onUseExistingCredentials,
        );
      case 2:
        // The chooser guarantees `_selectedProvider` is non-null before
        // the user can advance — fall back to nexus defensively if the
        // PageView reaches us out of order (e.g. hot-reload).
        return S3GetKeyStep(
          currentStep: 2,
          totalSteps: _totalSteps,
          provider: _selectedProvider ?? AiProviderType.nexus,
          onContinue: _next,
          onBack: _previous,
        );
      case 3:
        final provider = _selectedProvider ?? AiProviderType.nexus;
        return S4PasteKeyStep(
          // Re-key the step so initState fires when the user navigates
          // back from a failed test → otherwise the controller would
          // hang on to the previous key + clipboard banner state.
          key: ValueKey<String>(
            'paste_${provider.name}_${_pendingCredentials?.apiKey.hashCode ?? 0}',
          ),
          currentStep: 3,
          totalSteps: _totalSteps,
          provider: provider,
          initialApiKey: _pendingCredentials?.apiKey,
          initialModel: _pendingCredentials?.model,
          initialBaseUrl: _pendingCredentials?.baseUrl,
          onSubmit: _onPasteKeySubmitted,
          onBack: _previous,
        );
      case 4:
        final creds = _pendingCredentials;
        if (creds == null) {
          // Unreachable in normal flow — but keep the wizard usable if a
          // hot-reload wipes the in-flight credentials.
          return S1WelcomeStep(
            currentStep: 0,
            totalSteps: _totalSteps,
            onStart: () => _goTo(1),
            onLater: _exitWizard,
          );
        }
        return S5TestingStep(
          // Re-key on credential change so the test re-runs when the user
          // edits + re-submits.
          key: ValueKey<int>(
              creds.apiKey.hashCode ^ (creds.model?.hashCode ?? 0)),
          currentStep: 4,
          totalSteps: _totalSteps,
          credentials: creds,
          onSuccess: _onTestSucceeded,
          onEditKey: _onEditKeyAfterFailure,
        );
      case 5:
        final creds = _pendingCredentials;
        final model = _effectiveModel ?? creds?.model ?? '';
        if (creds == null) {
          return S1WelcomeStep(
            currentStep: 0,
            totalSteps: _totalSteps,
            onStart: () => _goTo(1),
            onLater: _exitWizard,
          );
        }
        return S6DoneStep(
          currentStep: 5,
          totalSteps: _totalSteps,
          credentials: creds,
          effectiveModel: model,
          onFinish: _exitWizard,
          onConfigureAnother: _onConfigureAnother,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
