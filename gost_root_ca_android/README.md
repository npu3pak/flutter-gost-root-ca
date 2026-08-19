# gost_root_ca_android

Endorsed-реализация `gost_root_ca` для Android.

Доверие к корню НУЦ Минцифры (Russian Trusted Root CA) обеспечивается
декларативно — через Network Security Config из манифеста плагина
(`res/xml/gost_network_security_config.xml`): системные корни + корень
Минцифры для всех нативных стеков (WebView, HttpURLConnection, OkHttp).
`enable()` — no-op.

Интеграция и ограничения — см. корневой `README.md`.
