import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nitido/app/common/widgets/user_avatar_display.dart';
import 'package:nitido/core/database/services/user-setting/user_setting_service.dart';
import 'package:nitido/core/presentation/theme.dart';
import 'package:nitido/core/presentation/widgets/user_avatar.dart';
import 'package:nitido/core/services/attachments/attachment_model.dart';
import 'package:nitido/core/services/attachments/attachments_service.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

Widget _wrap(Widget child) {
  return TranslationProvider(
    child: Builder(
      builder: (context) => MaterialApp(
        theme: getThemeData(
          context,
          isDark: false,
          amoledMode: false,
          lightDynamic: null,
          darkDynamic: null,
          accentColor: 'auto',
        ),
        locale: TranslationProvider.of(context).flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

File _createImageFile(String path, int red) {
  final raster = img.Image(width: 120, height: 120);
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      raster.setPixelRgba(x, y, red, 80, 120, 255);
    }
  }
  final file = File(path)..writeAsBytesSync(img.encodePng(raster));
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempRoot;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.en);
    appStateSettings[SettingKey.font] = '0';
    appStateSettings[SettingKey.accentColor] = 'auto';
    appStateSettings[SettingKey.amoledMode] = '0';
    appStateSettings[SettingKey.themeMode] = 'system';

    tempRoot = await Directory.systemTemp.createTemp('nitido_avatar_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempRoot.path;
      }
      return null;
    });

    await AttachmentsService.instance.deleteByOwner(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
    );
  });

  tearDown(() async {
    await AttachmentsService.instance.deleteByOwner(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);

    if (await tempRoot.exists()) {
      try {
        await tempRoot.delete(recursive: true);
      } on FileSystemException {
        // Ignore Windows file-lock races from shared DB handles in tests.
      }
    }
  });

  test('6.7 replace avatar leaves only latest row and file', () async {
    final firstSource = _createImageFile('${tempRoot.path}/avatar_a.png', 120);
    final secondSource = _createImageFile('${tempRoot.path}/avatar_b.png', 210);

    final first = await AttachmentsService.instance.attach(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      sourceFile: firstSource,
      role: 'avatar',
    );

    await AttachmentsService.instance.deleteById(first.id);

    final second = await AttachmentsService.instance.attach(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      sourceFile: secondSource,
      role: 'avatar',
    );

    final list = await AttachmentsService.instance.listByOwner(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
    );

    expect(list, hasLength(1));
    expect(list.first.id, second.id);

    final firstResolved = await AttachmentsService.instance.resolveFile(first);
    final secondResolved = await AttachmentsService.instance.resolveFile(second);

    expect(firstResolved.existsSync(), isFalse);
    expect(secondResolved.existsSync(), isTrue);
  });

  testWidgets('6.8 UserAvatarDisplay renders custom image or fallback preset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const UserAvatarDisplay(avatar: 'man')),
    );
    // UserAvatarDisplay uses FutureBuilder + Image.file. The image decode
    // pipeline schedules additional frames that prevent pumpAndSettle from
    // ever draining the frame queue, causing a ~112s hang. pump(2s) is
    // sufficient for both FutureBuilders and Image decode to complete.
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(UserAvatar), findsOneWidget);

    final customSource = _createImageFile('${tempRoot.path}/avatar_custom.png', 80);
    await AttachmentsService.instance.attach(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      sourceFile: customSource,
      role: 'avatar',
    );

    await tester.pumpWidget(
      _wrap(const UserAvatarDisplay(avatar: 'man')),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('6.9 use preset path removes custom avatar and falls back', (
    tester,
  ) async {
    final customSource = _createImageFile('${tempRoot.path}/avatar_to_remove.png', 60);
    final custom = await AttachmentsService.instance.attach(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      sourceFile: customSource,
      role: 'avatar',
    );

    await AttachmentsService.instance.deleteById(custom.id);

    await tester.pumpWidget(
      _wrap(const UserAvatarDisplay(avatar: 'woman')),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(UserAvatar), findsOneWidget);
  });

  test('6.10 no orphan files remain after avatar replace path', () async {
    final firstSource = _createImageFile('${tempRoot.path}/avatar_orphan_a.png', 100);
    final secondSource = _createImageFile('${tempRoot.path}/avatar_orphan_b.png', 180);

    final first = await AttachmentsService.instance.attach(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      sourceFile: firstSource,
      role: 'avatar',
    );

    await AttachmentsService.instance.deleteById(first.id);

    await AttachmentsService.instance.attach(
      ownerType: AttachmentOwnerType.userProfile,
      ownerId: 'current',
      sourceFile: secondSource,
      role: 'avatar',
    );

    final removed = await AttachmentsService.instance.purgeOrphans();
    expect(removed, 0);
  });
}
