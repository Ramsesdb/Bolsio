import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wallex/app/layout/page_switcher.dart';
import 'package:wallex/core/database/services/app-data/app_data_service.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/database/utils/personal_ve_seeders.dart';
import 'package:wallex/core/presentation/app_colors.dart';
import 'package:wallex/core/presentation/styles/big_button_style.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/auto_import/capture/device_quirks_service.dart';
import 'package:wallex/core/services/auto_import/capture/permission_coordinator.dart';
import 'package:wallex/core/utils/unique_app_widgets_keys.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

// ---------------------------------------------------------------------------
// Bank descriptor — onboarding selection model
// ---------------------------------------------------------------------------
class _BankOption {
  const _BankOption({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
  });
  final String id;
  final String name;
  final Color color;
  final IconData icon;
}

const _kBanks = <_BankOption>[
  _BankOption(
    id: 'bdv',
    name: 'Banco de Venezuela',
    color: Color(0xFF1A237E),
    icon: Icons.account_balance,
  ),
  _BankOption(
    id: 'banesco',
    name: 'Banesco',
    color: Color(0xFF003087),
    icon: Icons.account_balance,
  ),
  _BankOption(
    id: 'mercantil',
    name: 'Mercantil',
    color: Color(0xFFB71C1C),
    icon: Icons.account_balance,
  ),
  _BankOption(
    id: 'provincial',
    name: 'Provincial',
    color: Color(0xFF2E7D32),
    icon: Icons.account_balance,
  ),
  _BankOption(
    id: 'bnc',
    name: 'BNC',
    color: Color(0xFF00838F),
    icon: Icons.account_balance,
  ),
  _BankOption(
    id: 'banplus',
    name: 'Banplus',
    color: Color(0xFFEF6C00),
    icon: Icons.account_balance,
  ),
  _BankOption(
    id: 'bicentenario',
    name: 'Bicentenario',
    color: Color(0xFFC62828),
    icon: Icons.account_balance,
  ),
  _BankOption(
    id: 'bancamiga',
    name: 'Bancamiga',
    color: Color(0xFF6A1B9A),
    icon: Icons.account_balance,
  ),
  _BankOption(
    id: 'binance',
    name: 'Binance',
    color: Color(0xFFF3BA2F),
    icon: Icons.currency_bitcoin,
  ),
  _BankOption(
    id: 'zinli',
    name: 'Zinli',
    color: Color(0xFF6A1B9A),
    icon: Icons.wallet,
  ),
  _BankOption(
    id: 'reserve',
    name: 'Reserve',
    color: Color(0xFF1565C0),
    icon: Icons.wallet,
  ),
  _BankOption(
    id: 'paypal',
    name: 'PayPal',
    color: Color(0xFF003087),
    icon: Icons.payment,
  ),
];

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _currentPage = 0;
  final PageController _pageController = PageController();

  // Setup state shared between pages
  final Set<String> _selectedBankIds = {};
  String _selectedCurrency = 'USD'; // default USD
  bool _isFinishing = false;

  static const int _totalPages = 4;

  // ── Navigation helpers ──────────────────────────────────────────────────

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _prev() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);

    try {
      // 1. Set preferred currency
      await UserSettingService.instance.setItem(
        SettingKey.preferredCurrency,
        _selectedCurrency,
      );

      // 2. Seed accounts with selected banks
      await PersonalVESeeder.seedAll(
        selectedBankIds: _selectedBankIds.toList(),
      );

      // 3. Mark intro as seen
      await AppDataService.instance.setItem(
        AppDataKey.introSeen,
        '1',
        updateGlobalState: true,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFinishing = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error al configurar Wallex'),
          content: const Text(
            'No se pudieron crear las cuentas iniciales. '
            'Por favor intenta de nuevo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
      return;
    }

    // 4. Navigate
    if (mounted) {
      unawaited(RouteUtils.pushRoute(
        PageSwitcher(key: tabsPageKey),
        withReplacement: true,
      ));
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage >= _totalPages - 1;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FractionallySizedBox(
            widthFactor: screenWidth < 700 ? 1.0 : 700 / screenWidth,
            child: Scaffold(
              persistentFooterButtons: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Back button — hidden on first page
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _currentPage > 0
                          ? Container(
                              padding: const EdgeInsets.all(4),
                              child: IconButton.outlined(
                                onPressed: _prev,
                                icon: const Icon(Icons.arrow_back_rounded),
                                iconSize: 20,
                                style: ButtonStyle(
                                  fixedSize: const WidgetStatePropertyAll(
                                    Size(42, bigButtonStyleHeight),
                                  ),
                                  shape: WidgetStatePropertyAll(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: FilledButton.icon(
                          onPressed: _isFinishing
                              ? null
                              : (isLast ? _finish : _next),
                          icon: isLast && _isFinishing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  isLast
                                      ? Icons.rocket_launch_rounded
                                      : Icons.arrow_forward_rounded,
                                ),
                          iconAlignment: IconAlignment.end,
                          label: Text(
                            isLast ? 'Entrar a Wallex' : 'Siguiente',
                          ),
                          style: getBigButtonStyle(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              body: Column(
                children: [
                  // ── Progress indicator ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 16,
                      bottom: 4,
                      left: 16,
                      right: 16,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const expansionFactor = 4;
                        const spacing = 4;

                        return AnimatedSmoothIndicator(
                          activeIndex: _currentPage,
                          count: _totalPages,
                          effect: ExpandingDotsEffect(
                            dotHeight: 12,
                            radius: 2,
                            dotColor: AppColors.of(context)
                                .consistentPrimary
                                .withValues(alpha: 0.25),
                            activeDotColor:
                                AppColors.of(context).consistentPrimary,
                            spacing: spacing.toDouble(),
                            dotWidth: constraints.maxWidth /
                                    (_totalPages + expansionFactor - 1) -
                                spacing / _totalPages,
                            expansionFactor: expansionFactor.toDouble(),
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Pages ─────────────────────────────────────────────
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      children: [
                        _WelcomePage(key: const ValueKey('welcome')),
                        _PermissionsPage(key: const ValueKey('permissions')),
                        _SetupPage(
                          key: const ValueKey('setup'),
                          selectedBankIds: _selectedBankIds,
                          selectedCurrency: _selectedCurrency,
                          onBankToggled: (id) => setState(() {
                            if (_selectedBankIds.contains(id)) {
                              _selectedBankIds.remove(id);
                            } else {
                              _selectedBankIds.add(id);
                            }
                          }),
                          onCurrencyChanged: (c) =>
                              setState(() => _selectedCurrency = c),
                        ),
                        _ReadyPage(key: const ValueKey('ready')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1 — Welcome
// ---------------------------------------------------------------------------
class _WelcomePage extends StatelessWidget {
  const _WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),

          // App icon / logo
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.account_balance_wallet_rounded,
              size: 64,
              color: primary,
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'Bienvenido a Wallex',
            style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          Text(
            'Tus finanzas. Tu control.',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Feature badges
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _Badge(
                icon: Icons.trending_up_rounded,
                label: 'BCV en tiempo real',
                color: primary,
              ),
              _Badge(
                icon: Icons.currency_bitcoin,
                label: 'USDT de mercado',
                color: const Color(0xFFF3BA2F),
              ),
              _Badge(
                icon: Icons.wifi_off_rounded,
                label: '100% offline',
                color: AppColors.of(context).success,
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Feature highlights
          _FeatureTile(
            icon: Icons.security_rounded,
            title: 'Privacidad total',
            subtitle: 'Tus datos solo están en tu dispositivo',
            color: primary,
          ),
          const SizedBox(height: 12),
          _FeatureTile(
            icon: Icons.bolt_rounded,
            title: 'Auto-import inteligente',
            subtitle: 'Captura pagos desde notificaciones bancarias',
            color: const Color(0xFFF3BA2F),
          ),
          const SizedBox(height: 12),
          _FeatureTile(
            icon: Icons.lock_rounded,
            title: 'Modo oculto',
            subtitle: 'Protege cuentas privadas con PIN',
            color: AppColors.of(context).success,
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2 — Permissions
// ---------------------------------------------------------------------------
class _PermissionsPage extends StatefulWidget {
  const _PermissionsPage({super.key});

  @override
  State<_PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<_PermissionsPage>
    with WidgetsBindingObserver {
  CapturePermissionsState _perms = CapturePermissionsState.initial();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await PermissionCoordinator.instance.check();
    if (mounted) setState(() => _perms = s);
  }

  Future<void> _requestNotifications() async {
    if (_loading) return;
    setState(() => _loading = true);
    await PermissionCoordinator.instance.requestPostNotifications();
    await PermissionCoordinator.instance.requestNotificationListener();
    await _refresh();
    setState(() => _loading = false);
  }

  Future<void> _requestBattery() async {
    if (_loading) return;
    setState(() => _loading = true);
    await DeviceQuirksService.instance.openBatteryOptimizationSettings();
    // User returns to app → didChangeAppLifecycleState will refresh
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final notifGranted =
        _perms.notificationListener && _perms.postNotifications;
    final batteryGranted = _perms.batteryOptimizationsIgnored;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'Para sacar el máximo provecho',
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Estos permisos son opcionales pero recomendados.',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 28),

          // ── Notifications permission ──────────────────────────────────
          _PermissionTile(
            icon: Icons.notifications_active_rounded,
            title: 'Notificaciones bancarias',
            description: 'Auto-registra tus pagos al instante',
            granted: notifGranted,
            onActivate: _requestNotifications,
            loading: _loading,
          ),

          const SizedBox(height: 16),

          // ── Battery optimization permission ───────────────────────────
          _PermissionTile(
            icon: Icons.battery_saver_rounded,
            title: 'Segundo plano',
            description: 'Para capturar aunque la app esté cerrada',
            granted: batteryGranted,
            onActivate: _requestBattery,
            loading: _loading,
          ),

          const SizedBox(height: 24),

          // Footer note
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.45),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Puedes configurar esto después en Ajustes',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.45),
                      ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 3 — Setup (banks + currency)
// ---------------------------------------------------------------------------
class _SetupPage extends StatelessWidget {
  const _SetupPage({
    super.key,
    required this.selectedBankIds,
    required this.selectedCurrency,
    required this.onBankToggled,
    required this.onCurrencyChanged,
  });

  final Set<String> selectedBankIds;
  final String selectedCurrency;
  final ValueChanged<String> onBankToggled;
  final ValueChanged<String> onCurrencyChanged;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),

          // ── Section A: Banks ──────────────────────────────────────────
          Text(
            '¿Con qué bancos operas?',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Selecciona los que uses. Puedes cambiar esto después.',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55),
                ),
          ),
          const SizedBox(height: 16),

          // Selectable bank grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemCount: _kBanks.length,
            itemBuilder: (context, index) {
              final bank = _kBanks[index];
              final selected = selectedBankIds.contains(bank.id);

              return _BankChip(
                bank: bank,
                selected: selected,
                onTap: () => onBankToggled(bank.id),
              );
            },
          ),

          const SizedBox(height: 16),

          // Always-active cash accounts
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: primary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: primary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Siempre activos: Efectivo Bs · Efectivo USD',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65),
                        ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Section B: Currency ───────────────────────────────────────
          Text(
            '¿En qué moneda ves tus saldos?',
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _CurrencyCard(
                  flag: '🇺🇸',
                  label: 'Dólares',
                  code: 'USD',
                  selected: selectedCurrency == 'USD',
                  onTap: () => onCurrencyChanged('USD'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CurrencyCard(
                  flag: '🇻🇪',
                  label: 'Bolívares',
                  code: 'VES',
                  selected: selectedCurrency == 'VES',
                  onTap: () => onCurrencyChanged('VES'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 4 — Ready
// ---------------------------------------------------------------------------
class _ReadyPage extends StatelessWidget {
  const _ReadyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),

          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded, size: 52, color: primary),
            ),
          ),

          const SizedBox(height: 24),

          Center(
            child: Text(
              '¡Todo listo!',
              style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Wallex está configurado para ti',
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 32),

          // ── Included free ─────────────────────────────────────────────
          _FeatureSection(
            title: 'Incluido gratis',
            titleColor: AppColors.of(context).success,
            titleIcon: Icons.check_circle_rounded,
            items: const [
              _FeatureItem(
                icon: Icons.bar_chart_rounded,
                text: 'Transacciones, cuentas y presupuestos ilimitados',
              ),
              _FeatureItem(
                icon: Icons.trending_up_rounded,
                text: 'Tasas BCV y USDT en tiempo real',
              ),
              _FeatureItem(
                icon: Icons.notifications_active_rounded,
                text: 'Auto-import desde notificaciones bancarias',
              ),
              _FeatureItem(
                icon: Icons.lock_rounded,
                text: 'Modo oculto para cuentas privadas',
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Premium / API key ─────────────────────────────────────────
          _FeatureSection(
            title: 'Con tu API key',
            titleColor: primary,
            titleIcon: Icons.auto_awesome_rounded,
            items: const [
              _FeatureItem(
                icon: Icons.chat_bubble_rounded,
                text: 'Chat con IA para registrar gastos',
              ),
              _FeatureItem(
                icon: Icons.cloud_sync_rounded,
                text: 'Sync entre dispositivos',
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.onActivate,
    required this.loading,
  });
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onActivate;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final success = AppColors.of(context).success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted
              ? success.withValues(alpha: 0.35)
              : Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (granted ? success : primary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 22,
              color: granted ? success : primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (granted)
            Icon(Icons.check_circle_rounded, color: success, size: 22)
          else
            TextButton(
              onPressed: loading ? null : onActivate,
              style: TextButton.styleFrom(
                foregroundColor: primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Activar'),
            ),
        ],
      ),
    );
  }
}

class _BankChip extends StatelessWidget {
  const _BankChip({
    required this.bank,
    required this.selected,
    required this.onTap,
  });
  final _BankOption bank;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? bank.color.withValues(alpha: 0.18)
              : Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? bank.color.withValues(alpha: 0.6)
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.08),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              bank.icon,
              size: 22,
              color: selected
                  ? bank.color
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
            ),
            const SizedBox(height: 6),
            Text(
              bank.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? bank.color
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                    height: 1.2,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({
    required this.flag,
    required this.label,
    required this.code,
    required this.selected,
    required this.onTap,
  });
  final String flag;
  final String label;
  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.14)
              : Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? primary.withValues(alpha: 0.6)
                : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.08),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(flag, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
              code,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: selected
                        ? primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
            ),
            if (selected) ...[
              const SizedBox(height: 8),
              Icon(Icons.check_circle_rounded, color: primary, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({
    required this.title,
    required this.titleColor,
    required this.titleIcon,
    required this.items,
  });
  final String title;
  final Color titleColor;
  final IconData titleIcon;
  final List<_FeatureItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: titleColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: titleColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon, size: 16, color: titleColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.icon, size: 18, color: titleColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.text,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem {
  const _FeatureItem({required this.icon, required this.text});
  final IconData icon;
  final String text;
}
