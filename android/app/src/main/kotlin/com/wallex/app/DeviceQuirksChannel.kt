package com.wallex.app

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("DEVICE_QUIRKS_ERROR", e.message, null)
            }
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

    private fun openBatteryOptimization(context: Context): Boolean {
        // Preferred: whitelist panel. User must tap app -> "Don't optimize".
        val generic = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (tryStart(context, generic)) return true

        // Fallback: direct request dialog with our package URI.
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (tryStart(context, direct)) return true

        // Last-resort fallback: app details settings.
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
