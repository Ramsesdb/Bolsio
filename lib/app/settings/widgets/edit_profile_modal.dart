import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wallex/app/common/widgets/user_avatar_display.dart';
import 'package:wallex/core/database/services/user-setting/user_setting_service.dart';
import 'package:wallex/core/services/attachments/attachment_model.dart';
import 'package:wallex/core/services/attachments/attachments_service.dart';
import 'package:wallex/core/services/receipt_ocr/receipt_image_service.dart';
import 'package:wallex/core/presentation/widgets/bottom_sheet_footer.dart';
import 'package:wallex/core/presentation/widgets/modal_container.dart';
import 'package:wallex/core/presentation/widgets/tappable.dart';
import 'package:wallex/core/presentation/widgets/user_avatar.dart';
import 'package:wallex/core/routes/route_utils.dart';
import 'package:wallex/core/utils/text_field_utils.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

class EditProfileModal extends StatefulWidget {
  const EditProfileModal({super.key});

  @override
  State<EditProfileModal> createState() => _EditProfileModalState();
}

class _EditProfileModalState extends State<EditProfileModal> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();

  String? selectedAvatar;
  bool _hasCustomAvatar = false;
  bool _uploading = false;
  // Bumped every time the underlying avatar attachment changes so the
  // preview's FutureBuilder (inside UserAvatarDisplay) re-fetches.
  int _avatarVersion = 0;

  final List<String> allAvatars = [
    'man',
    'woman',
    'executive_man',
    'executive_woman',
    'blonde_man',
    'blonde_woman',
    'black_man',
    'black_woman',
    'woman_with_bangs',
    'man_with_goatee',
  ];

  @override
  void initState() {
    super.initState();

    selectedAvatar = appStateSettings[SettingKey.avatar];
    _nameController.value = TextEditingValue(
      text: appStateSettings[SettingKey.userName] ?? '',
    );

    _loadCustomAvatarState();
  }

  Future<void> _loadCustomAvatarState() async {
    final current = await AttachmentsService.instance.firstByOwner(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      role: 'avatar',
    );

    if (!mounted) return;
    setState(() {
      _hasCustomAvatar = current != null;
    });
  }

  Future<ImageSource?> _askImageSource() {
    final t = Translations.of(context);
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t.attachments.upload_from_gallery),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t.attachments.upload_from_camera),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
          ],
        );
      },
    );
  }

  Future<void> _uploadCustomAvatar() async {
    final source = await _askImageSource();
    if (source == null) return;

    final imageService = ReceiptImageService();
    final picked = await imageService.pickAndCompress(source: source);
    if (picked == null) return;

    if (!mounted) return;
    setState(() {
      _uploading = true;
    });

    try {
      final oldAttachment = await AttachmentsService.instance.firstByOwner(
        ownerType: AttachmentOwnerType.userProfile,
        ownerId: 'current',
        role: 'avatar',
      );

      if (oldAttachment != null) {
        await AttachmentsService.instance.deleteById(oldAttachment.id);
      }

      await AttachmentsService.instance.attach(
        ownerType: AttachmentOwnerType.userProfile,
        ownerId: 'current',
        sourceFile: picked,
        role: 'avatar',
      );

      if (picked.existsSync()) {
        picked.deleteSync();
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _hasCustomAvatar = true;
          _avatarVersion++;
        });
      }
    }

    if (!mounted) return;
    final t = Translations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.attachments.upload_from_gallery),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _usePresetAvatar() async {
    final current = await AttachmentsService.instance.firstByOwner(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      role: 'avatar',
    );

    if (current != null) {
      await AttachmentsService.instance.deleteById(current.id);
    }

    if (!mounted) return;
    setState(() {
      _hasCustomAvatar = false;
      _avatarVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);

    return ModalContainer(
      title: t.settings.edit_profile,
      showTitleDivider: true,
      bodyPadding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAvatarPreview(context),
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _nameController,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'User name *'),
              validator: (value) => fieldValidator(value, isRequired: true),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              textInputAction: TextInputAction.done,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _uploadCustomAvatar,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(t.profile.upload_custom_avatar),
            ),
          ),
          if (_hasCustomAvatar)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _usePresetAvatar,
                icon: const Icon(Icons.person_off_outlined),
                label: Text(t.profile.use_preset_avatar),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, // gap between adjacent cards
            runSpacing: 12, // gap between lines
            alignment: WrapAlignment.center,
            children: allAvatars
                .map((avatarName) => buildTappableAvatar(context, avatarName))
                .toList(),
          ),
        ],
      ),
      footer: BottomSheetFooter(
        onSaved: selectedAvatar == null
            ? null
            : () {
                if (_formKey.currentState!.validate()) {
                  _formKey.currentState!.save();

                  final userSettingsService = UserSettingService.instance;

                  Future.wait(
                    [
                      userSettingsService.setItem(
                        SettingKey.userName,
                        _nameController.text,
                      ),
                      userSettingsService.setItem(
                        SettingKey.avatar,
                        selectedAvatar!,
                        updateGlobalState: true,
                      ),
                    ].map((e) => Future.value(e)),
                  ).then((value) {
                    RouteUtils.popRoute();
                  });
                }
              },
      ),
    );
  }

  Widget _buildAvatarPreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const double previewSize = 96;

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: UserAvatarDisplay(
              // Bumping _avatarVersion changes the key, which forces
              // UserAvatarDisplay to rebuild and re-run its internal
              // FutureBuilder — so the preview reflects the latest attachment.
              key: ValueKey<String>(
                'avatar-preview-$_avatarVersion-${selectedAvatar ?? "none"}',
              ),
              avatar: selectedAvatar,
              size: previewSize,
              border: Border.all(width: 2, color: colorScheme.primary),
            ),
          ),
          if (_uploading)
            Container(
              width: previewSize + 8,
              height: previewSize + 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
              ),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Tappable buildTappableAvatar(BuildContext context, String avatarName) {
    return Tappable(
      borderRadius: BorderRadius.circular(888),
      bgColor: Theme.of(context).colorScheme.primaryContainer,
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          selectedAvatar = avatarName;
        });
      },
      child: UserAvatar(
        avatar: avatarName,
        size: 52,
        backgroundColor: Colors.transparent,
        border: selectedAvatar == avatarName
            ? Border.all(width: 2, color: Theme.of(context).colorScheme.primary)
            : Border.all(width: 2, color: Colors.transparent),
      ),
    );
  }
}
