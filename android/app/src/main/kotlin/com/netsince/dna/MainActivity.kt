package com.netsince.dna

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "com.netsince.dna/app_icon"
        private val ALIASES = listOf("MainActivityDefault", "MainActivityAlt")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "setIcon") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name")
                if (name == null || !ALIASES.contains(name)) {
                    result.error("INVALID_ALIAS", "Unknown alias: $name", null)
                    return@setMethodCallHandler
                }
                try {
                    val pm = packageManager
                    val packageName = applicationContext.packageName
                    // 先启用目标 alias，再禁用其余，避免桌面入口短暂消失导致“应用未安装”。
                    pm.setComponentEnabledSetting(
                        ComponentName(packageName, "$packageName.$name"),
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                    for (alias in ALIASES) {
                        if (alias == name) continue
                        pm.setComponentEnabledSetting(
                            ComponentName(packageName, "$packageName.$alias"),
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                            PackageManager.DONT_KILL_APP,
                        )
                    }
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SET_ICON_FAILED", e.message, null)
                }
            }
    }
}
