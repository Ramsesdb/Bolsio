import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nitido/app/calculator/calculator.page.dart';
import 'package:nitido/app/layout/page_framework.dart';
import 'package:nitido/app/settings/pages/appareance_settings.page.dart';
import 'package:nitido/app/settings/pages/ai/ai_settings.page.dart';
import 'package:nitido/app/settings/pages/backup/backup_settings.page.dart';
import 'package:nitido/app/settings/pages/auto_import/auto_import_settings.page.dart';
import 'package:nitido/app/settings/pages/general_settings.page.dart';
import 'package:nitido/app/settings/pages/hidden_mode_settings.page.dart';
import 'package:nitido/app/settings/pages/transactions_settings.page.dart';
import 'package:nitido/core/database/utils/personal_ve_seeders.dart';
import 'package:nitido/core/extensions/padding.extension.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/core/services/firebase_sync_service.dart';
import 'package:nitido/core/utils/logger.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {

  Future<void> _runPersonalVESeeder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Insertar datos de Venezuela'),
        content: const Text(
          'Se crearan cuentas bancarias venezolanas, categorias de '
          'ingreso/gasto y tags utiles.\n\n'
          'Si ya tienes cuentas creadas, no se insertara nada (idempotente).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Insertar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading overlay
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));

    try {
      await PersonalVESeeder.seedAll();

      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Datos de Venezuela insertados correctamente.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      Logger.printDebug('Settings: PersonalVESeeder error: $e');
      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al insertar datos: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PageFramework(
      title: t.settings.title_short,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16).withSafeBottom(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SettingRouteTile(
              title: t.settings.general.menu_title,
              subtitle: t.settings.general.menu_descr,
              icon: Icons.settings_rounded,
              onTap: () => RouteUtils.pushRoute(const GeneralSettingsPage()),
            ),
            const Divider(),
            _SettingRouteTile(
              title: t.settings.transactions.menu_title,
              subtitle: t.settings.transactions.menu_descr,
              icon: Icons.list,
              onTap: () =>
                  RouteUtils.pushRoute(const TransactionsSettingsPage()),
            ),
            const Divider(),
            _SettingRouteTile(
              title: t.settings.appearance.menu_title,
              subtitle: t.settings.appearance.menu_descr,
              icon: Icons.color_lens_rounded,
              onTap: () => RouteUtils.pushRoute(const AppareanceSettingsPage()),
            ),
            const Divider(),
            _SettingRouteTile(
              title: t.more.data.display,
              subtitle: t.more.data.display_descr,
              icon: Icons.save_rounded,
              onTap: () => RouteUtils.pushRoute(const BackupSettingsPage()),
            ),
            const Divider(),
            _SettingRouteTile(
              title: t.settings.hidden_mode.title,
              subtitle: t.settings.hidden_mode.menu_descr,
              icon: Icons.visibility_off_outlined,
              onTap: () =>
                  RouteUtils.pushRoute(const HiddenModeSettingsPage()),
            ),
            const Divider(),

            // ── Utilidades ────────────────────────────────────
            // Entry point Calculadora FX (calculadora-fx Tanda 1, task 1.7).
            _SettingRouteTile(
              title: t.calculator.title,
              subtitle: t.calculator.settings_subtitle,
              icon: Icons.calculate_outlined,
              onTap: () => RouteUtils.pushRoute(const CalculatorPage()),
            ),
            const Divider(),

            // ── Auto-import section ──────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
              child: Text(
                'Automatizacion',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _SettingRouteTile(
              title: t.settings.auto_import.menu_title,
              subtitle: 'Captura automatica de SMS, notificaciones y APIs',
              icon: Icons.auto_mode,
              onTap: () => RouteUtils.pushRoute(
                  const AutoImportSettingsPage()),
            ),
            const Divider(),

            _SectionHeader('Inteligencia Artificial'),
            _SettingRouteTile(
              title: 'Niti',
              subtitle: 'Categorizacion, insights y chat con IA',
              icon: Icons.auto_awesome_rounded,
              onTap: () => RouteUtils.pushRoute(const AiSettingsPage()),
            ),
            const Divider(),

            // ── Sync section ──────────────────────────────────
            _SectionHeader('Cuenta'),
            ListTile(
              leading: const Icon(Icons.cloud_done, size: 26),
              title: Text(
                FirebaseSyncService.instance.currentUserEmail != null
                    ? 'Conectado como ${FirebaseSyncService.instance.currentUserEmail}'
                    : 'Sin cuenta',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                FirebaseSyncService.instance.currentUserEmail != null
                    ? 'Datos sincronizados con Google'
                    : 'Inicia sesion para sincronizar tus datos',
              ),
            ),
            const Divider(),

            // ── Datos personales VE ──────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
              child: Text(
                'Datos iniciales',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance, size: 26),
              title: const Text(
                'Insertar datos de Venezuela',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Crea cuentas bancarias VE, categorias y tags predefinidos',
              ),
              onTap: _runPersonalVESeeder,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingRouteTile extends StatelessWidget {
  const _SettingRouteTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      leading: Icon(icon, size: 26),
      onTap: onTap,
    );
  }
}
