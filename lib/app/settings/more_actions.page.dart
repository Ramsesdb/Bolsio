import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bolsio/app/accounts/all_accounts_page.dart';
import 'package:bolsio/app/auth/welcome_screen.dart';
import 'package:bolsio/app/budgets/budgets_page.dart';
import 'package:bolsio/app/calculator/calculator.page.dart';
import 'package:bolsio/app/categories/categories_list_page.dart';
import 'package:bolsio/app/currencies/currency_manager.dart';
import 'package:bolsio/app/debts/debts_page.dart';
import 'package:bolsio/app/goals/goals_page.dart';
import 'package:bolsio/app/layout/page_framework.dart';
import 'package:bolsio/app/settings/about.page.dart';
import 'package:bolsio/app/settings/pages/ai/ai_settings.page.dart';
import 'package:bolsio/app/settings/pages/appareance_settings.page.dart';
import 'package:bolsio/app/settings/pages/auto_import/auto_import_settings.page.dart';
import 'package:bolsio/app/settings/pages/backup/backup_settings.page.dart';
import 'package:bolsio/app/settings/pages/general_settings.page.dart';
import 'package:bolsio/app/settings/pages/hidden_mode_settings.page.dart';
import 'package:bolsio/app/settings/pages/transactions_settings.page.dart';
import 'package:bolsio/app/settings/widgets/profile_hero_card.dart';
import 'package:bolsio/app/settings/widgets/setting_card_item.dart';
import 'package:bolsio/app/settings/widgets/settings_quick_access.dart';
import 'package:bolsio/app/settings/widgets/settings_search_bar.dart';
import 'package:bolsio/app/settings/widgets/bolsio_ai_hero_card.dart';
import 'package:bolsio/app/tags/tag_list.page.dart';
import 'package:bolsio/app/transactions/recurrent_transactions_page.dart';
import 'package:bolsio/core/database/services/app-data/app_data_service.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/database/utils/personal_ve_seeders.dart';
import 'package:bolsio/core/models/goal/goal.dart';
import 'package:bolsio/core/presentation/app_colors.dart';
import 'package:bolsio/core/presentation/responsive/breakpoints.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/core/services/firebase_sync_service.dart';
import 'package:bolsio/core/utils/logger.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';
import 'package:google_sign_in/google_sign_in.dart';

class MoreActionsPage extends StatefulWidget {
  const MoreActionsPage({super.key});

  @override
  State<MoreActionsPage> createState() => _MoreActionsPageState();
}

class _MoreActionsPageState extends State<MoreActionsPage> {
  String _searchQuery = '';
  late List<_SearchItem> _searchItems;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _searchItems = _buildSearchItems();
  }

  List<_SearchItem> _buildSearchItems() {
    final t = Translations.of(context);
    final sections = t.more.sections;
    return [
      _SearchItem(label: t.currencies.currency_manager, section: sections.configuration, icon: Icons.currency_exchange, onTap: () => RouteUtils.pushRoute(const CurrencyManagerPage())),
      _SearchItem(label: t.more.ai.title, section: sections.configuration, icon: Icons.auto_awesome, onTap: () => RouteUtils.pushRoute(const AiSettingsPage())),
      _SearchItem(label: t.settings.auto_import.menu_title, section: sections.configuration, icon: Icons.bolt_outlined, onTap: () => RouteUtils.pushRoute(const AutoImportSettingsPage())),
      _SearchItem(label: t.settings.appearance.menu_title, section: sections.configuration, icon: Icons.palette_outlined, onTap: () => RouteUtils.pushRoute(const AppareanceSettingsPage())),
      _SearchItem(label: t.settings.transactions.menu_title, section: sections.configuration, icon: Icons.swap_horiz, onTap: () => RouteUtils.pushRoute(const TransactionsSettingsPage())),
      _SearchItem(label: t.settings.hidden_mode.title, section: sections.configuration, icon: Icons.lock_outline, onTap: () => RouteUtils.pushRoute(const HiddenModeSettingsPage())),
      _SearchItem(label: t.settings.general.menu_title, section: sections.configuration, icon: Icons.language, onTap: () => RouteUtils.pushRoute(const GeneralSettingsPage())),
      _SearchItem(label: t.backup.export.title, section: sections.data, icon: Icons.upload_outlined, onTap: () => RouteUtils.pushRoute(const BackupSettingsPage())),
      _SearchItem(label: t.backup.import.title, section: sections.data, icon: Icons.download_outlined, onTap: () => RouteUtils.pushRoute(const BackupSettingsPage())),
      _SearchItem(label: t.more.account.firebase_sync, section: sections.data, icon: Icons.cloud_sync_outlined, onTap: () => RouteUtils.pushRoute(const BackupSettingsPage())),
      _SearchItem(label: t.calculator.title, section: sections.tools, icon: Icons.calculate_outlined, onTap: () => RouteUtils.pushRoute(const CalculatorPage())),
      _SearchItem(label: t.more.about_us.display, section: sections.about, icon: Icons.info_outline, onTap: () => RouteUtils.pushRoute(const AboutPage())),
      _SearchItem(label: t.general.accounts, section: sections.management, icon: Icons.account_balance_wallet_rounded, onTap: () => RouteUtils.pushRoute(const AllAccountsPage())),
      _SearchItem(label: t.general.categories, section: sections.management, icon: Icons.category_rounded, onTap: () => RouteUtils.pushRoute(const CategoriesListPage())),
      _SearchItem(label: t.tags.display(n: 2), section: sections.management, icon: Icons.label_outline_rounded, onTap: () => RouteUtils.pushRoute(const TagListPage())),
      _SearchItem(label: t.debts.display(n: 2), section: sections.management, icon: Icons.payments_rounded, onTap: () => RouteUtils.pushRoute(const DebtsPage())),
      _SearchItem(label: t.goals.title, section: sections.management, icon: Goal.icon, onTap: () => RouteUtils.pushRoute(const GoalsPage())),
      _SearchItem(label: t.budgets.title, section: sections.management, icon: Icons.pie_chart_rounded, onTap: () => RouteUtils.pushRoute(const BudgetsPage())),
      _SearchItem(label: t.recurrent_transactions.title_short, section: sections.management, icon: Icons.repeat_rounded, onTap: () => RouteUtils.pushRoute(const RecurrentTransactionPage())),
    ];
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (FirebaseSyncService.instance.isFirebaseAvailable) {
      try {
        await FirebaseSyncService.instance.signOut();
      } catch (_) {}
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
    }

    await AppDataService.instance.setItem(AppDataKey.onboarded, null, updateGlobalState: true);
    await AppDataService.instance.setItem(AppDataKey.introSeen, null, updateGlobalState: true);

    if (mounted) {
      unawaited(Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      ));
    }
  }

  Future<void> _runPersonalVESeeder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Insertar datos de Venezuela'),
        content: const Text(
          'Se crearán cuentas bancarias venezolanas, categorías de '
          'ingreso/gasto y tags útiles.\n\n'
          'Si ya tienes cuentas creadas, no se insertará nada (idempotente).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Insertar')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));

    try {
      await PersonalVESeeder.seedAll();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Datos de Venezuela insertados correctamente.'),
            backgroundColor: AppColors.of(context).success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      Logger.printDebug('MoreActions: PersonalVESeeder error: $e');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al insertar datos: $e'),
            backgroundColor: AppColors.of(context).danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteAllData() async {
    final t = Translations.of(context);

    final step1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.more.data.delete_all_header1),
        content: Text(t.more.data.delete_all_message1),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.ui_actions.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.of(context).danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.ui_actions.confirm),
          ),
        ],
      ),
    );
    if (step1 != true || !mounted) return;

    final step2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.more.data.delete_all_header2),
        content: Text(t.more.data.delete_all_message2),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.ui_actions.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.of(context).danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.ui_actions.confirm),
          ),
        ],
      ),
    );
    if (step2 != true || !mounted) return;

    await _handleSignOut();
  }

  Widget _sectionHeader(String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: AppColors.of(context).textHint,
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? titleColor,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = AppColors.of(context);

    return ListTile(
      leading: Icon(icon, color: iconColor ?? cs.primary),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(color: titleColor),
      ),
      trailing: Icon(Icons.chevron_right, color: appColors.textHint),
      onTap: onTap,
    );
  }

  Widget _settingsCard(List<Widget> tiles) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i < tiles.length - 1) const Divider(height: 1, indent: 56),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildManagementGrid() {
    final t = Translations.of(context);
    final isLarge = BreakPoint.of(context).isLargerThan(BreakpointID.sm);
    final isExtraLarge = BreakPoint.of(context).isLargerThan(BreakpointID.lg);

    final items = [
      _ActionItem(title: t.general.accounts, icon: Icons.account_balance_wallet_rounded, onTap: () => RouteUtils.pushRoute(const AllAccountsPage())),
      _ActionItem(title: t.general.categories, icon: Icons.category_rounded, onTap: () => RouteUtils.pushRoute(const CategoriesListPage())),
      _ActionItem(title: t.tags.display(n: 2), icon: Icons.label_outline_rounded, onTap: () => RouteUtils.pushRoute(const TagListPage())),
      _ActionItem(title: t.debts.display(n: 2), icon: Icons.payments_rounded, onTap: () => RouteUtils.pushRoute(const DebtsPage())),
      _ActionItem(title: t.goals.title, icon: Goal.icon, onTap: () => RouteUtils.pushRoute(const GoalsPage())),
      _ActionItem(title: t.budgets.title, icon: Icons.pie_chart_rounded, onTap: () => RouteUtils.pushRoute(const BudgetsPage())),
      _ActionItem(title: t.recurrent_transactions.title_short, icon: Icons.repeat_rounded, onTap: () => RouteUtils.pushRoute(const RecurrentTransactionPage())),
    ];

    int maxColumns = isExtraLarge ? 6 : (isLarge ? 4 : 3);
    final count = items.length;
    final numRows = (count / maxColumns).ceil();
    final basePerRow = count ~/ numRows;
    final extra = count % numRows;

    final rows = <Widget>[];
    int idx = 0;
    for (int r = 0; r < numRows; r++) {
      final size = basePerRow + (r < extra ? 1 : 0);
      if (idx + size > items.length) break;
      final chunk = items.sublist(idx, idx + size);
      idx += size;
      rows.add(Row(
        spacing: 8,
        children: chunk.map((item) => Expanded(
          child: SettingCardItem(
            title: item.title,
            icon: item.icon,
            onTap: item.onTap,
          ),
        )).toList(),
      ));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final appColors = AppColors.of(context);
    final preferredCurrency = appStateSettings[SettingKey.preferredCurrency];
    final isVes = preferredCurrency == 'VES';

    final filteredItems = _searchQuery.isEmpty
        ? <_SearchItem>[]
        : _searchItems.where((item) =>
            item.label.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return PageFramework(
      title: t.more.title_long,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            const ProfileHeroCard(),
            const BolsioAiHeroCard(),
            SettingsSearchBar(onChanged: (q) => setState(() => _searchQuery = q)),

            if (_searchQuery.isNotEmpty) ...[
              if (filteredItems.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Sin resultados para "$_searchQuery"',
                      style: TextStyle(color: appColors.textHint),
                    ),
                  ),
                )
              else
                ...filteredItems.map((item) => ListTile(
                  leading: Icon(item.icon, color: Theme.of(context).colorScheme.primary),
                  title: Text(item.label),
                  subtitle: Text(item.section, style: TextStyle(color: appColors.textHint)),
                  trailing: Icon(Icons.chevron_right, color: appColors.textHint),
                  onTap: item.onTap,
                )),
            ] else ...[

              // Quick access
              _sectionHeader(t.more.sections.quick_access),
              const SettingsQuickAccess(),

              // Gestión
              _sectionHeader(t.more.sections.management),
              ..._buildManagementGrid(),

              // Configuración
              _sectionHeader(t.more.sections.configuration),
              _settingsCard([
                _settingsTile(icon: Icons.currency_exchange, title: t.currencies.currency_manager, onTap: () => RouteUtils.pushRoute(const CurrencyManagerPage())),
                _settingsTile(icon: Icons.auto_awesome, title: t.more.ai.title, onTap: () => RouteUtils.pushRoute(const AiSettingsPage())),
                _settingsTile(icon: Icons.bolt_outlined, title: t.settings.auto_import.menu_title, onTap: () => RouteUtils.pushRoute(const AutoImportSettingsPage())),
                _settingsTile(icon: Icons.palette_outlined, title: t.settings.appearance.menu_title, onTap: () => RouteUtils.pushRoute(const AppareanceSettingsPage())),
                _settingsTile(icon: Icons.swap_horiz, title: t.settings.transactions.menu_title, onTap: () => RouteUtils.pushRoute(const TransactionsSettingsPage())),
                _settingsTile(icon: Icons.lock_outline, title: t.settings.hidden_mode.title, onTap: () => RouteUtils.pushRoute(const HiddenModeSettingsPage())),
                _settingsTile(icon: Icons.language, title: t.settings.general.menu_title, onTap: () => RouteUtils.pushRoute(const GeneralSettingsPage())),
              ]),

              // Datos
              _sectionHeader(t.more.sections.data),
              _settingsCard([
                _settingsTile(icon: Icons.upload_outlined, title: t.backup.export.title, onTap: () => RouteUtils.pushRoute(const BackupSettingsPage())),
                _settingsTile(icon: Icons.download_outlined, title: t.backup.import.title, onTap: () => RouteUtils.pushRoute(const BackupSettingsPage())),
                _settingsTile(icon: Icons.cloud_sync_outlined, title: t.more.account.firebase_sync, onTap: () => RouteUtils.pushRoute(const BackupSettingsPage())),
                if (isVes)
                  _settingsTile(icon: Icons.science_outlined, title: 'Datos de prueba Venezuela', onTap: _runPersonalVESeeder),
                _settingsTile(
                  icon: Icons.delete_forever_outlined,
                  title: t.more.data.delete_all,
                  titleColor: appColors.danger,
                  iconColor: appColors.danger,
                  onTap: _handleDeleteAllData,
                ),
              ]),

              // Herramientas
              _sectionHeader(t.more.sections.tools),
              _settingsCard([
                _settingsTile(icon: Icons.calculate_outlined, title: t.calculator.title, onTap: () => RouteUtils.pushRoute(const CalculatorPage())),
              ]),

              // Acerca de
              _sectionHeader(t.more.sections.about),
              _settingsCard([
                _settingsTile(icon: Icons.info_outline, title: t.more.about_us.display, onTap: () => RouteUtils.pushRoute(const AboutPage())),
              ]),

              // Footer
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.logout),
                    label: Text(t.more.account.sign_out),
                    style: TextButton.styleFrom(foregroundColor: appColors.danger),
                    onPressed: _handleSignOut,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchItem {
  final String label;
  final String section;
  final IconData icon;
  final VoidCallback onTap;

  const _SearchItem({
    required this.label,
    required this.section,
    required this.icon,
    required this.onTap,
  });
}

class _ActionItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  _ActionItem({required this.title, required this.icon, required this.onTap});
}
