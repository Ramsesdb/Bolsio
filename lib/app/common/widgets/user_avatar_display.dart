import 'dart:io';

import 'package:flutter/material.dart';
import 'package:bolsio/core/services/attachments/attachment_model.dart';
import 'package:bolsio/core/services/attachments/attachments_service.dart';
import 'package:bolsio/core/presentation/widgets/user_avatar.dart';

class UserAvatarDisplay extends StatelessWidget {
  const UserAvatarDisplay({
    super.key,
    this.avatar,
    this.size = 36,
    this.border,
    this.backgroundColor,
  });

  final String? avatar;
  final Border? border;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: AttachmentsService.instance.firstByOwner(
        ownerType: AttachmentOwnerType.userProfile,
        ownerId: 'current',
        role: 'avatar',
      ),
      builder: (context, snapshot) {
        final attachment = snapshot.data;
        if (attachment == null) {
          return UserAvatar(
            avatar: avatar,
            size: size,
            border: border,
            backgroundColor: backgroundColor,
          );
        }

        return FutureBuilder(
          future: AttachmentsService.instance.resolveFile(attachment),
          builder: (context, fileSnapshot) {
            final file = fileSnapshot.data;
            if (file == null || !file.existsSync()) {
              return UserAvatar(
                avatar: avatar,
                size: size,
                border: border,
                backgroundColor: backgroundColor,
              );
            }

            return _ImageAvatar(
              file: file,
              size: size,
              border: border,
              backgroundColor: backgroundColor,
            );
          },
        );
      },
    );
  }
}

class _ImageAvatar extends StatelessWidget {
  const _ImageAvatar({
    required this.file,
    required this.size,
    this.border,
    this.backgroundColor,
  });

  final File file;
  final Border? border;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(100),
        color: backgroundColor ?? colorScheme.primaryContainer,
        border: border,
      ),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          color: backgroundColor ?? colorScheme.primaryContainer,
        ),
        child: Image.file(
          file,
          height: size,
          width: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) {
            return UserAvatar(
              avatar: null,
              size: size,
              border: border,
              backgroundColor: backgroundColor,
            );
          },
        ),
      ),
    );
  }
}
