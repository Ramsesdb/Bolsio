import 'package:flutter/material.dart';
import 'package:nitido/app/layout/page_framework.dart';
import 'package:nitido/app/settings/widgets/settings_list_utils.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/extensions/padding.extension.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

class AppLockSettingsPage extends StatefulWidget {
  const AppLockSettingsPage({super.key});

  @override
  State<AppLockSettingsPage> createState() => _AppLockSettingsPageState();
}

class _AppLockSettingsPageState extends State<AppLockSettingsPage> {
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _biometricEnabled = appStateSettings[SettingKey.biometricEnabled] == '1';
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return PageFramework(
      title: t.settings.security.biometric.section_title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16).withSafeBottom(context),
        child: ListTileTheme(
          data: getSettingListTileStyle(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              createListSeparator(context, t.settings.security.biometric.section_title),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.fingerprint_outlined),
                title: Text(t.settings.security.biometric.title),
                subtitle: Text(t.settings.security.biometric.descr),
                value: _biometricEnabled,
                onChanged: (v) async {
                  await UserSettingService.instance.setItem(
                    SettingKey.biometricEnabled,
                    v ? '1' : '0',
                    updateGlobalState: true,
                  );
                  if (mounted) setState(() => _biometricEnabled = v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
