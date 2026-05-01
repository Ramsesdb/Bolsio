package com.nitido.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.app.FlutterApplication

/**
 * Application class for Nitido.
 *
 * Single responsibility: pre-create EVERY notification channel the app uses
 * BEFORE any code path can call `startForeground(...)` or `notify(...)`.
 *
 * Why this exists:
 *   `flutter_background_service_android` (BackgroundService.java) does NOT
 *   create the notification channel when the Dart side passes a custom
 *   `notificationChannelId`. It assumes the channel already exists. If it does
 *   not, Android 14+ rejects the foreground notification with
 *   `RemoteServiceException$CannotPostForegroundServiceNotificationException:
 *   Bad notification for startForeground` and kills the `:capture` process in
 *   a tight loop.
 *
 *   Three independent paths can trigger startForeground BEFORE the main Dart
 *   isolate runs `LocalNotificationService.initialize()`:
 *     1. `BootReceiver.kt` after device boot (no Activity, no main isolate).
 *     2. The plugin's internal `BootReceiver` / `WatchdogReceiver`.
 *     3. The `:capture` process spinning up faster than the main isolate's
 *        deferred `addPostFrameCallback` bootstrap (8s delay in main.dart).
 *
 *   The `nitido_pending` channel has the same risk: when the background
 *   isolate runs (in the `:capture` process) it calls
 *   `LocalNotificationService.showNewPendingNotification(...)` directly, and
 *   on a fresh install nothing in the `:capture` process has ever called
 *   `androidPlugin.createNotificationChannel(...)` yet — so the channel does
 *   not exist and the notification is silently dropped (or rejected).
 *
 *   Plus: the rebrand wallex -> nitido changed the package name from
 *   `com.bolsio.app` to `com.nitido.app`, which means every install is a
 *   fresh package with zero notification channels — there is no leftover
 *   channel from a previous app version to fall back on.
 *
 * Application.onCreate() runs in EVERY process the app spawns (including the
 * `:capture` process), so the channels are guaranteed to exist before
 * `BackgroundService.onCreate()` posts its first notification.
 *
 * Race-fix: channels are created BEFORE `super.onCreate()` so they exist
 * even if the framework starts dispatching service intents while the
 * Application init is still in flight. NotificationChannel registration is
 * a lightweight call against a system service — it does not require Flutter
 * or any app component to be initialized.
 *
 * The channel IDs, names, descriptions, and importance MUST stay in sync
 * with `LocalNotificationService` in lib/core/services/auto_import/background/.
 */
class NitidoApplication : FlutterApplication() {

    override fun onCreate() {
        // IMPORTANT: create channels BEFORE super.onCreate() so they exist
        // before the framework can dispatch any service start intent. The
        // NotificationManager system service is available at this point
        // (it's part of ContextImpl, attached during attachBaseContext()).
        ensureNotificationChannels()
        super.onCreate()
    }

    private fun ensureNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val nm = getSystemService(NotificationManager::class.java) ?: return

        // createNotificationChannel is idempotent: if a channel with the same
        // ID already exists, the system keeps user-facing settings (sound,
        // vibration, importance overrides) which is what we want.

        // Foreground service channel — low importance, silent, persistent.
        // Mirrors LocalNotificationService.captureChannelId in Dart.
        val capture = NotificationChannel(
            CAPTURE_CHANNEL_ID,
            CAPTURE_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = CAPTURE_CHANNEL_DESC
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        nm.createNotificationChannel(capture)

        // Pending-imports channel — default importance, sound + vibration,
        // shows badge. Mirrors LocalNotificationService.pendingChannelId
        // in Dart (importance: Importance.defaultImportance, playSound: true,
        // enableVibration: true, showBadge: true).
        val pending = NotificationChannel(
            PENDING_CHANNEL_ID,
            PENDING_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = PENDING_CHANNEL_DESC
            setShowBadge(true)
            enableVibration(true)
            val defaultSound: Uri = Settings.System.DEFAULT_NOTIFICATION_URI
            val audioAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(defaultSound, audioAttrs)
        }
        nm.createNotificationChannel(pending)
    }

    companion object {
        // MUST match LocalNotificationService.captureChannelId (Dart).
        private const val CAPTURE_CHANNEL_ID = "nitido_capture"
        private const val CAPTURE_CHANNEL_NAME = "Captura de movimientos"
        private const val CAPTURE_CHANNEL_DESC =
            "Notificacion persistente del servicio de captura"

        // MUST match LocalNotificationService.pendingChannelId (Dart).
        private const val PENDING_CHANNEL_ID = "nitido_pending"
        private const val PENDING_CHANNEL_NAME = "Movimientos por revisar"
        private const val PENDING_CHANNEL_DESC =
            "Notificaciones cuando se capturan nuevos movimientos"
    }
}
