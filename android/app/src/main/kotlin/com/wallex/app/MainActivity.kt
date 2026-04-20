package com.wallex.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Tanda 3: OEM-specific deep-links for autostart / battery optimization.
        DeviceQuirksChannel.register(applicationContext, flutterEngine)
    }
}
