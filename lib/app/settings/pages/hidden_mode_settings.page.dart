import 'package:flutter/material.dart';
import 'package:nitido/app/layout/page_framework.dart';
import 'package:nitido/app/settings/widgets/pin_modal.dart';
import 'package:nitido/app/settings/widgets/settings_list_utils.dart';
import 'package:nitido/app/settings/widgets/nitido_tile_switch.dart';
import 'package:nitido/core/database/services/user-setting/hidden_mode_service.dart';
import 'package:nitido/core/extensions/padding.extension.dart';
import 'package:nitido/core/presentation/helpers/snackbar.dart';
import 'package:nitido/i18n/generated/translations.g.dart';

/// Settings page to enable/disable Hidden Mode and rotate the PIN.
///
/// Reads the current enabled flag via [HiddenModeService.isEnabled] (async —
/// see [initState]) and refreshes after any toggle / change action so the
/// switch and the "Change PIN" tile stay in sync with the service state.
class HiddenModeSettingsPage extends StatefulWidget {
  const HiddenModeSettingsPage({super.key});

  @override
  State<HiddenModeSettingsPage> createState() => _HiddenModeSettingsPageState();
}

class _HiddenModeSettingsPageState extends State<HiddenModeSettingsPage> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _loadEnabled();
  }

  Future<void> _loadEnabled() async {
    final value = await HiddenModeService.instance.isEnabled();
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  Future<void> _handleSwitch(bool value) async {
    if (value) {
      final newPin = await showSetupPinModal(context);
      if (newPin == null) {
        // User dismissed the setup sheet — make sure the switch reverts.
        if (mounted) setState(() => _enabled = false);
        return;
      }
      // setPin is already called inside the modal's confirm handler. No need
      // to call it again; just refresh the flag.
      await _loadEnabled();
    } else {
      final pin = await showConfirmDisableModal(context);
      if (pin == null) {
        if (mounted) setState(() => _enabled = true);
        return;
      }
      try {
        await HiddenModeService.instance.disableHiddenMode(pin);
      } catch (_) {
        // disableHiddenMode re-validates and can throw if the pin changed
        // between the modal and this call. Fall back to the real flag.
      }
      await _loadEnabled();
    }
  }

  Future<void> _handleChangePin() async {
    final changed = await showChangePinModal(context);
    if (!mounted) return;
    if (changed) {
      final t = Translations.of(context);
      NitidoSnackbar.info(SnackbarParams(t.settings.hidden_mode.pin.pin_changed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final isEnabled = _enabled ?? false;

    return PageFramework(
      title: t.settings.hidden_mode.title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16).withSafeBottom(context),
        child: ListTileTheme(
          data: getSettingListTileStyle(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              createListSeparator(context, t.settings.hidden_mode.title),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  t.settings.hidden_mode.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (_enabled == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                NitidoTileSwitch(
                  title: t.settings.hidden_mode.enable,
                  subtitle: isEnabled
                      ? t.settings.hidden_mode.enabled_badge
                      : null,
                  icon: Icon(
                    isEnabled
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  initialValue: isEnabled,
                  onSwitch: _handleSwitch,
                ),
                if (isEnabled)
                  ListTile(
                    leading: const Icon(Icons.lock_reset_outlined),
                    title: Text(t.settings.hidden_mode.change_pin),
                    subtitle: Text(t.settings.hidden_mode.change_pin_descr),
                    onTap: _handleChangePin,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
