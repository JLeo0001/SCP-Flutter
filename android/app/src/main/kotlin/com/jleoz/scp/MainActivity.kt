package com.jleoz.scp

import android.view.ActionMode
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// 阅读页框选文字时由 Dart 侧开启:吞掉系统文字选择菜单(ActionMode),
    /// 改用应用内 Win11 风格框选菜单。Dart 侧通过 scp_app/selection_gate 控制。
    private var suppressSelectionMenu = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scp_app/selection_gate")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSuppress") {
                    suppressSelectionMenu = call.argument<Boolean>("value") ?: false
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActionModeStarted(mode: ActionMode) {
        if (suppressSelectionMenu) {
            mode.finish()
        }
        super.onActionModeStarted(mode)
    }
}
