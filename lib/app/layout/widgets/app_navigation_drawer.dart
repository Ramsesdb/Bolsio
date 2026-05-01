import 'package:flutter/material.dart';
import 'package:nitido/app/common/widgets/user_avatar_display.dart';
import 'package:nitido/app/layout/window_bar.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/extensions/color.extensions.dart';
import 'package:nitido/core/presentation/app_colors.dart';
import 'package:nitido/core/routes/destinations.dart';
import 'package:nitido/core/utils/app_utils.dart';

/// Sidebar navigation drawer used in desktop layouts only
class SideNavigationDrawer extends StatelessWidget {
  const SideNavigationDrawer({
    super.key,
    required this.selectedIndex,
    this.onDestinationSelected,
    required this.drawerActions,
  });

  final int selectedIndex;
  final List<MainMenuDestination> drawerActions;
  final void Function(int)? onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return DrawerTheme(
      data: const DrawerThemeData(shape: RoundedRectangleBorder()),
      child: NavigationDrawer(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        backgroundColor: getWindowBackgroundColor(context),
        indicatorColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        header: SizedBox(height: AppUtils.isDesktop ? 8 : 12),
        footer: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            spacing: 12,
            children: [
              UserAvatarDisplay(
                avatar: appStateSettings[SettingKey.avatar],
                backgroundColor: AppColors.of(
                  context,
                ).onConsistentPrimary.darken(0.25),
                border: Border.all(
                  width: 2,
                  color: AppColors.of(context).onConsistentPrimary,
                ),
              ),
              Expanded(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(0),
                  title: Text(
                    appStateSettings[SettingKey.userName] ?? 'User',
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleSmall!.copyWith(
                      fontSize: 18,
                      overflow: TextOverflow.fade,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  subtitle: Text('Thanks for trust us ❤️'),
                ),
              ),
            ],
          ),
        ),
        children: List.generate(drawerActions.length, (index) {
          final item = drawerActions[index];

          return item.toNavigationDrawerDestinationWidget();
        }),
      ),
    );
  }
}
