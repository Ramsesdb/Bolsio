import 'dart:async';

import 'package:bolsio/core/database/services/user-setting/user_setting_service.dart';
import 'package:rxdart/rxdart.dart';

class PrivateModeService {
  final UserSettingService userSettingsService;

  PrivateModeService._(this.userSettingsService);
  static final PrivateModeService instance = PrivateModeService._(
    UserSettingService.instance,
  );

  final _privateModeController = BehaviorSubject<bool>();
  Stream<bool> get privateModeStream => _privateModeController.stream;

  void dispose() {
    _privateModeController.close();
  }

  Future<void> setPrivateMode(bool value) async {
    _privateModeController.add(value);
    await userSettingsService.setItem(
      SettingKey.privateMode,
      value ? '1' : '0',
      updateGlobalState: false,
    );
  }

  /// Set if the app should start in private mode
  Future<bool> setPrivateModeAtLaunch(bool value) async {
    final result = await userSettingsService.setItem(
      SettingKey.privateModeAtLaunch,
      value ? '1' : '0',
    );

    return result;
  }
}
