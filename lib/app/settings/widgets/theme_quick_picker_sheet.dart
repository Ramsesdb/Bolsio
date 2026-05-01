import 'package:flutter/material.dart';
import 'package:nitido/app/settings/pages/appareance_settings.page.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/database/services/user-setting/utils/get_theme_from_string.dart';
import 'package:nitido/core/routes/route_utils.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

Future<void> showThemeQuickPickerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ThemeQuickPickerContent(),
  );
}

class _ThemeQuickPickerContent extends StatefulWidget {
  const _ThemeQuickPickerContent();

  @override
  State<_ThemeQuickPickerContent> createState() =>
      _ThemeQuickPickerContentState();
}

class _ThemeQuickPickerContentState extends State<_ThemeQuickPickerContent> {
  late ThemeMode _themeMode;
  late bool _amoled;

  @override
  void initState() {
    super.initState();
    _themeMode = getThemeFromString(appStateSettings[SettingKey.themeMode]);
    _amoled = appStateSettings[SettingKey.amoledMode] == '1';
  }

  Future<void> _setTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await UserSettingService.instance.setItem(
      SettingKey.themeMode,
      mode.name,
      updateGlobalState: true,
    );
  }

  Future<void> _setAmoled(bool value) async {
    setState(() => _amoled = value);
    await UserSettingService.instance.setItem(
      SettingKey.amoledMode,
      value ? '1' : '0',
      updateGlobalState: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = Translations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(
              t.more.theme.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ThemeChip(
                  label: t.more.theme.system,
                  icon: Icons.brightness_auto,
                  selected: _themeMode == ThemeMode.system,
                  onTap: () => _setTheme(ThemeMode.system),
                ),
                _ThemeChip(
                  label: t.more.theme.light,
                  icon: Icons.light_mode,
                  selected: _themeMode == ThemeMode.light,
                  onTap: () => _setTheme(ThemeMode.light),
                ),
                _ThemeChip(
                  label: t.more.theme.dark,
                  icon: Icons.dark_mode,
                  selected: _themeMode == ThemeMode.dark,
                  onTap: () => _setTheme(ThemeMode.dark),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              title: Text(t.more.theme.amoled),
              value: _amoled,
              onChanged: _themeMode == ThemeMode.light ? null : _setAmoled,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(t.more.theme.more_options),
                onPressed: () {
                  Navigator.pop(context);
                  RouteUtils.pushRoute(const AppareanceSettingsPage());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest,
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(icon, size: 22, color: selected ? cs.primary : cs.onSurface),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? cs.primary : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
