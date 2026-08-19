# gost_root_ca_ios

Endorsed-реализация `gost_root_ca` для iOS.

Доверие к корню НУЦ Минцифры (Russian Trusted Root CA) обеспечивается
method swizzling'ом: делегаты URLSession-сессий и `navigationDelegate`
WKWebView оборачиваются в прокси, перехватывающий только server trust
challenge (схема как в TrustKit). Свиззлы и встроенный корень
(`GostBuiltinRootCert.swift`) ставятся при регистрации плагина — до старта
Dart; `GostRootCa.enable()` из Dart переопределяет корень при необходимости.

Интеграция и ограничения — см. корневой `README.md`.
