import 'package:flutter/material.dart';
import 'package:wallex/app/layout/page_framework.dart';
import 'package:wallex/app/settings/pages/appareance_settings.page.dart';
import 'package:wallex/app/settings/pages/backup/backup_settings.page.dart';
import 'package:wallex/app/settings/pages/general_settings.page.dart';
import 'package:wallex/app/settings/pages/transactions_settings.page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:wallex/core/extensions/padding.extension.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
