import 'package:flutter/material.dart';
import 'package:kilatex/app/common/widgets/user_avatar_display.dart';
import 'package:kilatex/app/settings/widgets/edit_profile_modal.dart';
import 'package:kilatex/core/database/services/user-setting/user_setting_service.dart';
import 'package:kilatex/core/presentation/app_colors.dart';
import 'package:kilatex/core/presentation/widgets/tappable.dart';
import 'package:kilatex/core/services/firebase_sync_service.dart';

class ProfileHeroCard extends StatelessWidget {
  const ProfileHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final brightness = theme.brightness;

    final userName = appStateSettings[SettingKey.userName];
    final avatar = appStateSettings[SettingKey.avatar];
    final syncEnabled = appStateSettings[SettingKey.firebaseSyncEnabled] == '1';
    final email = FirebaseSyncService.instance.currentUserEmail;

    return Tappable(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const EditProfileModal(),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(
                alpha: brightness == Brightness.dark ? 0.06 : 0.10,
              ),
              Colors.transparent,
            ],
          ),
          border: Border.all(color: theme.dividerColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          spacing: 12,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.30),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: UserAvatarDisplay(avatar: avatar, size: 56),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Text(
                    userName?.isNotEmpty == true ? userName! : 'Tu cuenta',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    email ?? 'Sin cuenta vinculada',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appColors.textHint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    spacing: 4,
                    children: [
                      Icon(
                        syncEnabled ? Icons.cloud_done : Icons.cloud_off,
                        size: 13,
                        color: syncEnabled
                            ? appColors.success
                            : appColors.textHint,
                      ),
                      Text(
                        syncEnabled ? 'Sincronizado' : 'Sincronización desactivada',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 18, color: appColors.textHint),
          ],
        ),
      ),
    );
  }
}
