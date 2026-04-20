import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wallex/core/presentation/widgets/confirm_dialog.dart';
import 'package:wallex/core/services/voice/voice_service.dart';
import 'package:wallex/core/services/voice/voice_service_speech_to_text.dart';
import 'package:wallex/i18n/generated/translations.g.dart';

/// Outcome of the microphone permission flow.
enum VoicePermissionOutcome {
  /// Permission was already granted or was granted just now.
  granted,

  /// User dismissed the explainer or denied the OS prompt.
  denied,

  /// `permanentlyDenied` / MIUI locked — user was sent to app settings.
  sentToSettings,
}

/// First-run explainer + MIUI-aware microphone permission flow.
///
/// Mirrors the camera permission dialog in `new_transaction_fl_button.dart`,
/// but adds a first-run rationale modal (voice-input spec §permission-explainer).
///
/// Typical usage:
/// ```dart
/// final outcome = await ensureMicPermissionWithExplainer(context);
/// if (outcome != VoicePermissionOutcome.granted) return;
/// await VoiceService.instance.startSession();
/// ```
Future<VoicePermissionOutcome> ensureMicPermissionWithExplainer(
  BuildContext context, {
  VoiceService? service,
}) async {
  final voice = service ?? SpeechToTextVoiceService.instance;
  final t = Translations.of(context);

  final current = await Permission.microphone.status;

  if (current.isGranted) return VoicePermissionOutcome.granted;

  if (current.isPermanentlyDenied) {
    if (!context.mounted) return VoicePermissionOutcome.denied;
    return _showOpenSettingsDialog(context);
  }

  // First-run / previously-denied: show explainer, then OS prompt.
  if (!context.mounted) return VoicePermissionOutcome.denied;
  final accepted = await confirmDialog(
    context,
    dialogTitle: t.wallex_ai.voice_permission_title,
    contentParagraphs: [Text(t.wallex_ai.voice_permission_body)],
    confirmationText: t.wallex_ai.voice_permission_cta,
    showCancelButton: true,
  );

  if (accepted != true) return VoicePermissionOutcome.denied;

  final result = await voice.ensurePermission();
  if (result.isGranted) return VoicePermissionOutcome.granted;

  if (result.isPermanentlyDenied) {
    if (!context.mounted) return VoicePermissionOutcome.denied;
    return _showOpenSettingsDialog(context);
  }

  return VoicePermissionOutcome.denied;
}

Future<VoicePermissionOutcome> _showOpenSettingsDialog(
  BuildContext context,
) async {
  final t = Translations.of(context);
  final confirmed = await confirmDialog(
    context,
    dialogTitle: t.wallex_ai.voice_permission_denied_title,
    contentParagraphs: [Text(t.wallex_ai.voice_permission_denied_body)],
    confirmationText: t.wallex_ai.voice_permission_open_settings,
    showCancelButton: true,
  );

  if (confirmed == true) {
    await openAppSettings();
    return VoicePermissionOutcome.sentToSettings;
  }
  return VoicePermissionOutcome.denied;
}

/// Surfaces a "mic permission denied" snackbar with an "Open settings" action.
/// Call this from voice entry points when [ensureMicPermissionWithExplainer]
/// returns anything other than [VoicePermissionOutcome.granted] AND the user
/// did not already accept the open-settings CTA (i.e. [denied] outcome).
void showMicPermissionDeniedSnackbar(BuildContext context) {
  if (!context.mounted) return;
  final t = Translations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(t.wallex_ai.voice_permission_denied_snackbar),
      action: SnackBarAction(
        label: t.wallex_ai.voice_permission_open_settings,
        onPressed: () => openAppSettings(),
      ),
      duration: const Duration(seconds: 5),
    ),
  );
}
