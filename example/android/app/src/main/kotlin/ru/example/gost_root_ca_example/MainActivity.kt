package ru.example.gost_root_ca_example

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MainActivity.flutterEngineRef = flutterEngine
        setupNativeTlsTestChannel(flutterEngine)
        setupNativeWebViewStatusChannel(flutterEngine)
    }

    private fun setupNativeTlsTestChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gost_root_ca_example/native_tls_test"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("invalid_arguments", "url is missing", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        checkUrl(url, result)
                    }.start()
                }

                "openNativeWebView" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("invalid_arguments", "url is missing", null)
                        return@setMethodCallHandler
                    }
                    startActivity(
                        Intent(this, NativeWebViewActivity::class.java).putExtra("url", url)
                    )
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun setupNativeWebViewStatusChannel(flutterEngine: FlutterEngine) {
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gost_root_ca_example/native_webview_status"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                MainActivity.nativeWebViewEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                MainActivity.nativeWebViewEventSink = null
            }
        })
    }

    private fun checkUrl(url: String, result: MethodChannel.Result) {
        try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            try {
                val statusCode = connection.responseCode
                result.success(mapOf("success" to true, "statusCode" to statusCode))
            } finally {
                connection.disconnect()
            }
        } catch (e: Exception) {
            result.success(mapOf("success" to false, "error" to (e.message ?: e.toString())))
        }
    }

    companion object {
        @Volatile
        var flutterEngineRef: FlutterEngine? = null

        @Volatile
        var nativeWebViewEventSink: EventChannel.EventSink? = null
    }
}
