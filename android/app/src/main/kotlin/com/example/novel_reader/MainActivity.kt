package com.example.novel_reader

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "novel_reader/tts_keep_alive"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startTtsKeepAliveService()
                        result.success(null)
                    }
                    "stop" -> {
                        stopTtsKeepAliveService()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
