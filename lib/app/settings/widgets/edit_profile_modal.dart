import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:bolsio/core/services/attachments/attachment_model.dart';
import 'package:bolsio/core/services/attachments/attachments_service.dart';
import 'package:bolsio/core/services/receipt_ocr/receipt_image_service.dart';
import 'package:bolsio/core/routes/route_utils.dart';
import 'package:bolsio/core/utils/text_field_utils.dart';
import 'package:bolsio/i18n/generated/translations.g.dart';

const double _kHeroAvatarSize = 110;
const double _kTileSpacing = 12;
const double _kRowGap = 12;
const int _kNameMaxLength = 20;

const List<String> _kPresetAvatars = [
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

class EditProfileModal extends StatefulWidget {
  const EditProfileModal({super.key});

  @override
  State<EditProfileModal> createState() => _EditProfileModalState();
}

class _EditProfileModalState extends State<EditProfileModal> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  String? _selectedPreset;
  bool _uploadedPhotoSelected = false;
  File? _customAvatarFile;
  bool _uploading = false;
  int _customAvatarVersion = 0;

  @override
  void initState() {
    super.initState();
    final storedAvatar = appStateSettings[SettingKey.avatar];
    // Treat empty string (set when an uploaded photo was saved) as "no preset".
    _selectedPreset = (storedAvatar == null || storedAvatar.isEmpty)
        ? null
        : storedAvatar;
    _nameController.value = TextEditingValue(
      text: appStateSettings[SettingKey.userName] ?? '',
    );
    _nameController.addListener(() => setState(() {}));
    _loadCustomAvatar();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomAvatar() async {
    final attachment = await AttachmentsService.instance.firstByOwner(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      role: 'avatar',
    );
    if (attachment == null) {
      if (!mounted) return;
      setState(() {
        _customAvatarFile = null;
        _uploadedPhotoSelected = false;
      });
      return;
    }
    final file = await AttachmentsService.instance.resolveFile(attachment);
    if (!mounted) return;
    setState(() {
      _customAvatarFile = file.existsSync() ? file : null;
      // The uploaded attachment is the source of truth (matches
      // UserAvatarDisplay semantics outside the modal). If a stored custom
      // photo exists, it is the active selection and the preset is cleared
      // so the hero and tile #1 reflect the same state the user sees on the
      // dashboard / settings.
      if (_customAvatarFile != null) {
        _uploadedPhotoSelected = true;
        _selectedPreset = null;
      }
    });
  }

  Future<ImageSource?> _askImageSource() {
    final t = Translations.of(context);
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Column(
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
      ),
    );
  }

  Future<void> _uploadCustomAvatar() async {
    final source = await _askImageSource();
    if (source == null) return;

    final picked = await ReceiptImageService().pickAndCompress(source: source);
    if (picked == null) return;

    if (!mounted) return;
    setState(() => _uploading = true);

    try {
      final old = await AttachmentsService.instance.firstByOwner(
        ownerType: AttachmentOwnerType.userProfile,
        ownerId: 'current',
        role: 'avatar',
      );
      if (old != null) {
        await AttachmentsService.instance.deleteById(old.id);
      }
      await AttachmentsService.instance.attach(
        ownerType: AttachmentOwnerType.userProfile,
        ownerId: 'current',
        sourceFile: picked,
        role: 'avatar',
      );
      if (picked.existsSync()) picked.deleteSync();

      final saved = await AttachmentsService.instance.firstByOwner(
        ownerType: AttachmentOwnerType.userProfile,
        ownerId: 'current',
        role: 'avatar',
      );
      final resolved = saved == null
          ? null
          : await AttachmentsService.instance.resolveFile(saved);
      if (!mounted) return;
      setState(() {
        _customAvatarFile = (resolved != null && resolved.existsSync())
            ? resolved
            : null;
        _uploadedPhotoSelected = _customAvatarFile != null;
        _customAvatarVersion++;
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _selectPreset(String name) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedPreset = name;
      _uploadedPhotoSelected = false;
    });
  }

  void _selectUploadedPhoto() {
    if (_customAvatarFile == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _uploadedPhotoSelected = true;
    });
  }

  bool get _canSave {
    final hasSelection = _uploadedPhotoSelected || _selectedPreset != null;
    final name = _nameController.text.trim();
    return hasSelection && name.isNotEmpty;
  }

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final svc = UserSettingService.instance;

    if (_uploadedPhotoSelected) {
      // Custom photo wins. Clear the preset key so other surfaces fall back
      // to the attachment-based avatar.
      await svc.setItem(SettingKey.userName, _nameController.text);
      await svc.setItem(
        SettingKey.avatar,
        '',
        updateGlobalState: true,
      );
    } else {
      // Preset wins. Drop any uploaded attachment so the preset shows.
      final existing = await AttachmentsService.instance.firstByOwner(
        ownerType: AttachmentOwnerType.userProfile,
        ownerId: 'current',
        role: 'avatar',
      );
      if (existing != null) {
        await AttachmentsService.instance.deleteById(existing.id);
      }
      await svc.setItem(SettingKey.userName, _nameController.text);
      await svc.setItem(
        SettingKey.avatar,
        _selectedPreset!,
        updateGlobalState: true,
      );
    }

    if (!mounted) return;
    RouteUtils.popRoute();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: t.settings.edit_profile),
          Divider(height: 1, thickness: 1, color: cs.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroAvatar(
                    presetName: _uploadedPhotoSelected
                        ? null
                        : _selectedPreset,
                    customFile: _uploadedPhotoSelected
                        ? _customAvatarFile
                        : null,
                    uploading: _uploading,
                    accent: cs.primary,
                    surface: cs.surfaceContainerHigh,
                  ),
                  const SizedBox(height: 18),
                  _NameField(
                    controller: _nameController,
                    formKey: _formKey,
                    label: t.profile.name_label,
                    accent: cs.primary,
                    secondary: cs.onSurfaceVariant,
                    tertiary: cs.outline,
                  ),
                  const SizedBox(height: 24),
                  _PickerHeading(
                    label: t.profile.your_avatar,
                    aside: t.profile.options_count(
                      count: (_customAvatarFile != null ? 12 : 11).toString(),
                    ),
                    secondary: cs.onSurfaceVariant,
                    tertiary: cs.outline,
                  ),
                  const SizedBox(height: 12),
                  _AvatarGrid(
                    presets: _kPresetAvatars,
                    selectedPreset: _uploadedPhotoSelected
                        ? null
                        : _selectedPreset,
                    customFile: _customAvatarFile,
                    uploadedSelected: _uploadedPhotoSelected,
                    customAvatarVersion: _customAvatarVersion,
                    onSelectPreset: _selectPreset,
                    onSelectUploaded: _selectUploadedPhoto,
                    onUpload: _uploading ? null : _uploadCustomAvatar,
                    uploadLabel: _customAvatarFile != null
                        ? t.profile.replace_photo
                        : t.profile.upload_photo,
                    pinLabel: t.profile.your_photo_badge,
                  ),
                ],
              ),
            ),
          ),
          _Footer(
            cancelLabel: t.ui_actions.cancel,
            saveLabel: t.ui_actions.save,
            onCancel: () => RouteUtils.popRoute(),
            onSave: _canSave ? _onSave : null,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.nunito(
            textStyle: Theme.of(context).textTheme.titleLarge,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({
    required this.presetName,
    required this.customFile,
    required this.uploading,
    required this.accent,
    required this.surface,
  });

  final String? presetName;
  final File? customFile;
  final bool uploading;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: _kHeroAvatarSize,
        height: _kHeroAvatarSize,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _kHeroAvatarSize,
              height: _kHeroAvatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.05),
                    blurRadius: 0,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.025),
                    blurRadius: 0,
                    spreadRadius: 6,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipOval(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _buildContent(),
                ),
              ),
            ),
            // Subtle accent ring kissing the avatar to indicate active selection.
            IgnorePointer(
              child: Container(
                width: _kHeroAvatarSize + 2,
                height: _kHeroAvatarSize + 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
              ),
            ),
            if (uploading)
              Container(
                width: _kHeroAvatarSize,
                height: _kHeroAvatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.35),
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (customFile != null) {
      return Image.file(
        customFile!,
        key: ValueKey<String>('hero-custom-${customFile!.path}'),
        fit: BoxFit.cover,
        width: _kHeroAvatarSize,
        height: _kHeroAvatarSize,
      );
    }
    if (presetName != null) {
      return SvgPicture.asset(
        'assets/icons/avatars/$presetName.svg',
        key: ValueKey<String>('hero-preset-$presetName'),
        width: _kHeroAvatarSize,
        height: _kHeroAvatarSize,
      );
    }
    return const SizedBox.shrink(key: ValueKey<String>('hero-empty'));
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.formKey,
    required this.label,
    required this.accent,
    required this.secondary,
    required this.tertiary,
  });

  final TextEditingController controller;
  final GlobalKey<FormState> formKey;
  final String label;
  final Color accent;
  final Color secondary;
  final Color tertiary;

  @override
  Widget build(BuildContext context) {
    final length = controller.text.characters.length;
    final nunito = GoogleFonts.nunito(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: Theme.of(context).colorScheme.onSurface,
    );

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.centerRight,
            children: [
              TextFormField(
                controller: controller,
                maxLength: _kNameMaxLength,
                textAlign: TextAlign.center,
                cursorColor: accent,
                style: nunito,
                validator: (v) => fieldValidator(v, isRequired: true),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  contentPadding: const EdgeInsets.fromLTRB(28, 6, 28, 8),
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: accent.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: accent.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                ),
              ),
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 6),
                  child: Icon(Icons.edit_outlined, size: 14, color: tertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 11.5, color: tertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$length / $_kNameMaxLength',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: tertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerHeading extends StatelessWidget {
  const _PickerHeading({
    required this.label,
    required this.aside,
    required this.secondary,
    required this.tertiary,
  });

  final String label;
  final String aside;
  final Color secondary;
  final Color tertiary;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.12 * 12,
            color: secondary,
          ).copyWith(letterSpacing: 1.4),
        ),
        Text(
          aside,
          style: TextStyle(
            fontSize: 11.5,
            color: tertiary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _AvatarGrid extends StatelessWidget {
  const _AvatarGrid({
    required this.presets,
    required this.selectedPreset,
    required this.customFile,
    required this.uploadedSelected,
    required this.customAvatarVersion,
    required this.onSelectPreset,
    required this.onSelectUploaded,
    required this.onUpload,
    required this.uploadLabel,
    required this.pinLabel,
  });

  final List<String> presets;
  final String? selectedPreset;
  final File? customFile;
  final bool uploadedSelected;
  final int customAvatarVersion;
  final void Function(String) onSelectPreset;
  final VoidCallback onSelectUploaded;
  final VoidCallback? onUpload;
  final String uploadLabel;
  final String pinLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[];

    if (customFile != null) {
      tiles.add(
        _UploadedTile(
          file: customFile!,
          version: customAvatarVersion,
          selected: uploadedSelected,
          accent: cs.primary,
          surface: cs.surfaceContainerHighest,
          sheetBg: cs.surface,
          checkOn: cs.onPrimary,
          pinLabel: pinLabel,
          onTap: onSelectUploaded,
        ),
      );
    }

    for (final name in presets) {
      tiles.add(
        _PresetTile(
          name: name,
          selected: !uploadedSelected && selectedPreset == name,
          accent: cs.primary,
          surface: cs.surfaceContainerHighest,
          sheetBg: cs.surface,
          checkOn: cs.onPrimary,
          onTap: () => onSelectPreset(name),
        ),
      );
    }

    tiles.add(
      _UploadTile(
        accent: cs.primary,
        secondary: cs.onSurfaceVariant,
        tertiary: cs.outline,
        label: uploadLabel,
        onTap: onUpload,
      ),
    );

    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: _kRowGap,
      crossAxisSpacing: _kTileSpacing,
      childAspectRatio: 0.82,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }
}

class _TileFrame extends StatelessWidget {
  const _TileFrame({
    required this.child,
    required this.selected,
    required this.accent,
    required this.surface,
    required this.sheetBg,
    required this.checkOn,
    required this.onTap,
    this.label,
    this.pinLabel,
    this.dashed = false,
  });

  final Widget child;
  final bool selected;
  final Color accent;
  final Color surface;
  final Color sheetBg;
  final Color checkOn;
  final VoidCallback? onTap;
  final String? label;
  final String? pinLabel;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final tertiary = Theme.of(context).colorScheme.outline;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dashed ? Colors.transparent : surface,
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: accent,
                                blurRadius: 0,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: accent.withValues(alpha: 0.10),
                                blurRadius: 0,
                                spreadRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                    child: dashed
                        ? CustomPaint(
                            painter: _DashedCirclePainter(
                              color: Colors.white.withValues(alpha: 0.18),
                              strokeWidth: 1.5,
                            ),
                            child: Center(child: child),
                          )
                        : ClipOval(child: child),
                  ),
                  if (selected)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                          border: Border.all(color: sheetBg, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.check, size: 12, color: checkOn),
                      ),
                    ),
                  if (pinLabel != null)
                    Positioned(
                      top: 2,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: sheetBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            pinLabel!,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            Text(
              label!,
              style: TextStyle(fontSize: 10.5, color: tertiary),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.name,
    required this.selected,
    required this.accent,
    required this.surface,
    required this.sheetBg,
    required this.checkOn,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final Color accent;
  final Color surface;
  final Color sheetBg;
  final Color checkOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      selected: selected,
      accent: accent,
      surface: surface,
      sheetBg: sheetBg,
      checkOn: checkOn,
      onTap: onTap,
      child: SvgPicture.asset(
        'assets/icons/avatars/$name.svg',
        fit: BoxFit.cover,
      ),
    );
  }
}

class _UploadedTile extends StatelessWidget {
  const _UploadedTile({
    required this.file,
    required this.version,
    required this.selected,
    required this.accent,
    required this.surface,
    required this.sheetBg,
    required this.checkOn,
    required this.pinLabel,
    required this.onTap,
  });

  final File file;
  final int version;
  final bool selected;
  final Color accent;
  final Color surface;
  final Color sheetBg;
  final Color checkOn;
  final String pinLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      selected: selected,
      accent: accent,
      surface: surface,
      sheetBg: sheetBg,
      checkOn: checkOn,
      onTap: onTap,
      pinLabel: pinLabel,
      child: Image.file(
        file,
        key: ValueKey<String>('uploaded-$version-${file.path}'),
        fit: BoxFit.cover,
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.accent,
    required this.secondary,
    required this.tertiary,
    required this.label,
    required this.onTap,
  });

  final Color accent;
  final Color secondary;
  final Color tertiary;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _TileFrame(
      selected: false,
      accent: accent,
      surface: cs.surfaceContainerHighest,
      sheetBg: cs.surface,
      checkOn: cs.onPrimary,
      onTap: onTap,
      dashed: true,
      label: label,
      child: Icon(Icons.file_upload_outlined, size: 28, color: secondary),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final radius = size.width / 2 - strokeWidth / 2;
    final center = Offset(size.width / 2, size.height / 2);
    const dashCount = 28;
    const sweepPerSegment = (2 * 3.14159265358979) / dashCount;
    const dashFraction = 0.55;

    for (int i = 0; i < dashCount; i++) {
      final start = i * sweepPerSegment;
      final sweep = sweepPerSegment * dashFraction;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.cancelLabel,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
  });

  final String cancelLabel;
  final String saveLabel;
  final VoidCallback onCancel;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 14 + bottomInset),
        child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            key: const ValueKey('edit-profile-cancel'),
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: const StadiumBorder(),
            ),
            child: Text(cancelLabel),
          ),
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.check, size: 18),
            label: Text(saveLabel),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              disabledBackgroundColor: cs.surfaceContainerHigh,
              disabledForegroundColor: cs.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
