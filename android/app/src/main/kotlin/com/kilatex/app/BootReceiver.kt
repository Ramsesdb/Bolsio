package com.kilatex.app

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * Boots the Wallex capture foreground service when the device finishes booting.
 *
 * MIUI / HyperOS (and similar OEM skins) aggressively silence the auto-start
 * mechanism that ships with `flutter_background_service` — our service was
 * relying on `AndroidConfiguration(autoStartOnBoot: true)`, which registers a
 * receiver *inside the plugin module*. In practice, on POCO X7 Pro with
 * HyperOS the plugin's receiver is among the first to be killed by MIUI's
 * "App vigilance" heuristics, so the listener never wakes up after overnight
 * Doze + reboot cycles.
 *
 * This receiver lives under the app's own package so MIUI's package-level
 * autostart whitelist (toggled by the user via the `DeviceQuirksChannel`
 * deep-link) applies to it. Having BOTH the plugin's internal receiver AND
 * this one is intentional redundancy: on MIUI the user only needs ONE of
 * them to survive OEM pruning. On other OEMs the duplication is a no-op
 * (idempotent: startForegroundService + isRunning check in Dart).
 *
 * Triggered by:
 *   - `android.intent.action.BOOT_COMPLETED` — standard AOSP boot event
 *   - `android.intent.action.QUICKBOOT_POWERON` — Xiaomi/MIUI quick-boot path
 *     (fires on HyperOS devices where full BOOT_COMPLETED may be suppressed)
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        if (SystemClock.elapsedRealtime() > 60_000L) return
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != QUICKBOOT_POWERON
        ) {
            return
        }

        try {
            // flutter_background_service registers its foreground service as
            // `id.flutter.flutter_background_service.BackgroundService`. We
            // start it directly so the plugin's onStart() entry-point runs
            // and wires up the orchestrator just like the normal cold start.
            val serviceIntent = Intent().apply {
                component = ComponentName(
                    context.packageName,
                    BACKGROUND_SERVICE_CLASS,
                )
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            Log.i(TAG, "Boot-triggered capture service start ($action)")
        } catch (e: Exception) {
            // Never crash in a boot receiver — the OS penalizes apps that do.
            Log.w(TAG, "Failed to start capture service on boot: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "WallexBootReceiver"
        private const val QUICKBOOT_POWERON =
            "android.intent.action.QUICKBOOT_POWERON"
        private const val BACKGROUND_SERVICE_CLASS =
            "id.flutter.flutter_background_service.BackgroundService"
    }
}
