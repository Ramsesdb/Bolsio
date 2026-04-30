import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kilatex/app/settings/pages/auto_import/auto_import_settings.page.dart';
import 'package:kilatex/app/settings/widgets/theme_quick_picker_sheet.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/database/services/user-setting/utils/get_theme_from_string.dart';
import 'package:kilatex/core/presentation/app_colors.dart';
import 'package:kilatex/core/routes/route_utils.dart';
import 'package:kilatex/i18n/generated/translations.g.dart';

class SettingsQuickAccess extends StatefulWidget {
  const SettingsQuickAccess({super.key});

  @override
  State<SettingsQuickAccess> createState() => _SettingsQuickAccessState();
}

class _SettingsQuickAccessState extends State<SettingsQuickAccess> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final appColors = AppColors.of(context);
    final privateMode = appStateSettings[SettingKey.privateMode] == '1';
    final autoImport = appStateSettings[SettingKey.autoImportEnabled] == '1';

    final themeMode = getThemeFromString(appStateSettings[SettingKey.themeMode]);
    final IconData themeIcon;
    switch (themeMode) {
      case ThemeMode.light:
        themeIcon = Icons.light_mode;
        break;
      case ThemeMode.dark:
        themeIcon = Icons.dark_mode;
        break;
      default:
        themeIcon = Icons.brightness_auto;
    }
    final themeLabel = themeMode.displayName(context);
    final t = Translations.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(Icons.visibility_off_outlined, color: cs.primary),
            title: Text(t.settings.security.private_mode),
            trailing: Switch.adaptive(
              value: privateMode,
              onChanged: (v) async {
                await UserSettingService.instance.setItem(
                  SettingKey.privateMode,
                  v ? '1' : '0',
                  updateGlobalState: true,
                );
                if (mounted) setState(() {});
              },
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(themeIcon, color: cs.primary),
            title: Text(t.more.theme.title),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Text(
                  themeLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appColors.textHint,
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: appColors.textHint),
              ],
            ),
            onTap: () async {
              await showThemeQuickPickerSheet(context);
              if (mounted) setState(() {});
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(Icons.bolt_outlined, color: cs.primary),
            title: Text(t.settings.auto_import.menu_title),
            trailing: Switch.adaptive(
              value: autoImport,
              onChanged: (v) async {
                await UserSettingService.instance.setItem(
                  SettingKey.autoImportEnabled,
                  v ? '1' : '0',
                  updateGlobalState: true,
                );
                if (mounted) setState(() {});
                if (v && mounted) {
                  unawaited(RouteUtils.pushRoute(const AutoImportSettingsPage()));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
