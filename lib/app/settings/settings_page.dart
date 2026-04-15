import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wallex/app/layout/page_framework.dart';
import 'package:wallex/app/settings/pages/appareance_settings.page.dart';
import 'package:wallex/app/settings/pages/backup/backup_settings.page.dart';
import 'package:wallex/app/settings/pages/general_settings.page.dart';
import 'package:wallex/app/settings/pages/transactions_settings.page.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/database/utils/personal_ve_seeders.dart';
import 'package:wallex/core/extensions/padding.extension.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/services/firebase_sync_service.dart';
import 'package:wallex/core/utils/logger.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _syncEnabled;

  @override
  void initState() {
    super.initState();
    _syncEnabled =
        appStateSettings[SettingKey.firebaseSyncEnabled] == '1';
  }

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

  Future<void> _onSyncToggled(bool value) async {
    setState(() => _syncEnabled = value);

    await FirebaseSyncService.instance.setSyncEnabled(value);

    if (!mounted) return;

    if (value) {
      // Turning ON — warn that app restart is needed for Firebase init
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sync activado. Reinicia la app para conectar con Firebase.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sync desactivado. Tus datos siguen siendo locales.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
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

            // ── Sync section ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
              child: Text(
                'Sincronizacion (opcional)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_sync, size: 26),
              title: const Text(
                'Firebase Sync',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Sincroniza datos con Google (requiere configuracion Firebase)',
              ),
              value: _syncEnabled,
              onChanged: _onSyncToggled,
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

class _SettingRouteTile extends StatelessWidget {
  const _SettingRouteTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Function() onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      leading: Icon(icon, size: 26, color: iconColor),
      onTap: onTap,
    );
  }
}
