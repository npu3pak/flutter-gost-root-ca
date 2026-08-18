package ru.example.gost_root_ca_example

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout

/// Нативный WebView поверх Flutter-экрана. Статус загрузки отправляется
/// в Dart через EventChannel `gost_root_ca_example/native_webview_status`.
/// Доверие к корню Минцифры обеспечивается Network Security Config плагина.
class NativeWebViewActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val url = intent.getStringExtra("url") ?: run {
            finish()
            return
        }

        val closeButton = Button(this).apply {
            text = "Закрыть"
            setOnClickListener { finish() }
        }

        val webView = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            settings.javaScriptEnabled = true
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    sendStatus("load_finished", url, null)
                }

                @Suppress("DEPRECATION")
                override fun onReceivedError(
                    view: WebView?,
                    errorCode: Int,
                    description: String?,
                    failingUrl: String?
                ) {
                    sendStatus("load_failed", failingUrl, "$errorCode $description")
                }

                override fun onReceivedError(
                    view: WebView?,
                    request: WebResourceRequest?,
                    error: WebResourceError?
                ) {
                    sendStatus(
                        "load_failed",
                        request?.url?.toString(),
                        "${error?.errorCode} ${error?.description}"
                    )
                }
            }
            loadUrl(url)
        }

        val layout = FrameLayout(this).apply {
            addView(webView)
            addView(
                closeButton,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.END
                    marginEnd = 16
                    topMargin = 32
                }
            )
        }

        setContentView(layout)
    }

    private fun sendStatus(event: String, url: String?, error: String?) {
        val payload = mutableMapOf<String, String>("event" to event, "url" to (url ?: ""))
        if (error != null) {
            payload["error"] = error
        }
        MainActivity.nativeWebViewEventSink?.success(payload)
    }
}
