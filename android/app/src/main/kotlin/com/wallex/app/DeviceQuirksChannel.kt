package com.wallex.app

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel that exposes OEM-specific deep-links for critical background
 * permissions (autostart + battery optimization) required by the notification
 * listener pipeline on devices like Xiaomi/MIUI.
 *
 * Registered from [MainActivity.configureFlutterEngine].
 */
object DeviceQuirksChannel {
    const val CHANNEL_NAME = "com.wallex.capture/quirks"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "openAutostart" -> {
                        val quirk = call.argument<String>("quirk") ?: "none"
                        val opened = openAutostart(context, quirk)
                        result.success(opened)
                    }
                    "openBatteryOptimization" -> {
                        val opened = openBatteryOptimization(context)
                        result.success(opened)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations(context))
                    }
                    "openAppDetails" -> {
                        val opened = openAppDetails(context)
                        result.success(opened)
                    }
                    "openNotificationListenerSettings" -> {
                        openNotificationListenerSettings(context)
                        result.success(null)
                    }
                    "isRestrictedSettingsAllowed" -> {
                        result.success(isRestrictedSettingsAllowed(context))
                    }
                    "getDeviceVendor" -> {
                        result.success(getDeviceVendor())
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("DEVICE_QUIRKS_ERROR", e.message, null)
            }
        }
    }

    /**
     * Coarse OEM family bucket used to vary onboarding copy where the system
     * UI diverges meaningfully from stock Android (e.g. MIUI/HyperOS places
     * the "Allow restricted settings" toggle at the bottom of App info, not
     * behind a top-right kebab menu).
     *
     * Returns `"xiaomi"` for Xiaomi/Redmi/POCO devices, `"stock"` otherwise.
     */
    private fun getDeviceVendor(): String {
        val mfr = Build.MANUFACTURER.lowercase()
        return when {
            mfr.contains("xiaomi") || mfr.contains("redmi") || mfr.contains("poco") -> "xiaomi"
            else -> "stock"
        }
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        return try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                ?: return false
            pm.isIgnoringBatteryOptimizations(context.packageName)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Best-effort detection of Android's "Allow restricted settings" gate via
     * an **installer-source heuristic**.
     *
     * Background: the canonical AppOps check
     * (`unsafeCheckOpNoThrow("android:access_restricted_settings", uid, pkg)`)
     * is unviable for regular apps because the OS gates that op on the
     * caller holding `MANAGE_APPOPS` / `GET_APP_OPS_STATS` /
     * `MANAGE_APP_OPS_MODES` — all system-app permissions. Production logcat
     * confirmed it throws `SecurityException("verifyIncomingOp: uid <X> does
     * not have any of {MANAGE_APPOPS, GET_APP_OPS_STATS, MANAGE_APP_OPS_MODES}")`
     * on every device, falling into a fail-open branch that skipped the
     * slide for everyone. See `openspec/changes/restricted-settings-onboarding/design.md`
     * § "Detection: post-mortem" for the full write-up.
     *
     * The replacement heuristic asks: was the app installed by a trusted
     * source (Play Store, vendor app store)? If yes, Android does NOT apply
     * the restricted-settings gate, so we can return `true` and skip the
     * slide. If the installer is null, unknown, or any sideload-style source
     * (`com.google.android.packageinstaller`, ADB, etc.), we assume the gate
     * is active and return `false` so the slide is shown.
     *
     * Trade-off: a user with `ACCESS_RESTRICTED_SETTINGS=allow` already
     * granted but installed via a non-trusted installer will see the slide
     * once. They can dismiss with "Skip for now" — strictly better than the
     * AppOps approach which silently skipped the slide for every restricted
     * user.
     *
     * Pre-API-33 devices return `true` unconditionally — the
     * "Allow restricted settings" gate is an Android 13+ behavior.
     */
    private fun isRestrictedSettingsAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val trustedInstallers = setOf(
            "com.android.vending",          // Google Play Store
            "com.google.android.feedback",  // Play Internal / sideload from Play
            "com.huawei.appmarket",         // Huawei AppGallery
            "com.amazon.venezia",           // Amazon Appstore
            "com.sec.android.app.samsungapps", // Samsung Galaxy Store
        )
        return try {
            val installer: String? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    context.packageManager
                        .getInstallSourceInfo(context.packageName)
                        .installingPackageName
                } else {
                    @Suppress("DEPRECATION")
                    context.packageManager.getInstallerPackageName(context.packageName)
                }
            val allowed = installer != null && installer in trustedInstallers
            Log.d(
                "DeviceQuirks",
                "isRestrictedSettingsAllowed: installer=$installer → allowed=$allowed",
            )
            allowed
        } catch (e: Exception) {
            Log.d(
                "DeviceQuirks",
                "isRestrictedSettingsAllowed failed (treating as sideload): $e",
            )
            false
        }
    }

    private fun openBatteryOptimization(context: Context): Boolean {
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (tryStart(context, direct)) return true

        val generic = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (tryStart(context, generic)) return true

        return openAppDetails(context)
    }

    private fun openAppDetails(context: Context): Boolean {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return tryStart(context, intent)
    }

    /**
     * Opens the system "Notification access" screen where the user can
     * enable Wallex as a notification listener. Throws on failure so the
     * Dart side can fall back to [openAppDetails] with a toast instruction.
     *
     * On Android 11+ (API 30+) we use ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS
     * with the Wallex listener component so the user lands directly on our
     * app's toggle instead of the generic list of all installed apps.
     * The listener is provided by the `notification_listener_service` plugin
     * and registered in AndroidManifest.xml as
     * `notification.listener.service.NotificationListener`.
     */
    private fun openNotificationListenerSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val component = ComponentName(
                    context.packageName,
                    "notification.listener.service.NotificationListener",
                )
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                    .putExtra(
                        Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                        component.flattenToString(),
                    )
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                return
            } catch (_: Exception) {
                // Fallback to generic intent below if detail settings is not
                // available on this device.
            }
        }
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /**
     * OEM-specific autostart panels. When the component changes between
     * firmware versions, `tryStart` fails quietly and we fall through to the
     * next candidate, ultimately to the app details screen so the user is not
     * left on a blank screen.
     */
    private fun openAutostart(context: Context, quirk: String): Boolean {
        val candidates: List<ComponentName> = when (quirk.lowercase()) {
            "miui", "hyperos" -> listOf(
                // Canonical MIUI Security center autostart panel.
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                ),
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.appmanager.ApplicationsDetailsActivity",
                ),
            )
            "huawei" -> listOf(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                ),
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity",
                ),
            )
            "oppo", "realme" -> listOf(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                ),
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.startupapp.StartupAppListActivity",
                ),
                ComponentName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity",
                ),
            )
            "vivo" -> listOf(
                ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                ),
                ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                ),
            )
            "samsung" -> listOf(
                // Samsung doesn't have a single canonical autostart panel;
                // battery optimization whitelist is the closest proxy.
                ComponentName(
                    "com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity",
                ),
            )
            else -> emptyList()
        }

        for (component in candidates) {
            val intent = Intent().apply {
                this.component = component
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                when (quirk.lowercase()) {
                    "miui", "hyperos" -> {
                        putExtra("package_name", context.packageName)
                        putExtra("packageName", context.packageName)
                    }
                    "huawei" -> {
                        putExtra("packageName", context.packageName)
                    }
                    "samsung" -> {
                        putExtra("extra_pkgname", context.packageName)
                    }
                    "oppo", "realme", "vivo" -> {
                        putExtra("package_name", context.packageName)
                        putExtra("packageName", context.packageName)
                    }
                }
            }
            if (tryStart(context, intent)) return true
        }

        // Fallback: app details settings.
        return openAppDetails(context)
    }

    private fun tryStart(context: Context, intent: Intent): Boolean {
        return try {
            // On Android 11+, queries{} in the manifest governs what we can
            // resolve; swallow SecurityException just in case the OEM screen
            // is hidden.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // resolveActivity returns null if the activity is not
                // reachable; still try startActivity in that case.
                intent.resolveActivity(context.packageManager)
            }
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }
}
