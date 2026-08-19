# gost_root_ca_example

Тестовое приложение для `gost_root_ca`: 5 поверхностей × 2 URL.

Поверхности: REST Flutter (dart:io HttpClient), REST нативный
(MethodChannel: iOS URLSession / Android HttpURLConnection), WebView Flutter
(webview_flutter), WebView нативный (iOS WKWebView / Android WebView),
изображения (Image.network). URL: https://ya.ru и https://www.sberbank.ru/.

Запуск: `flutter run`. Доверие к корню НУЦ Минцифры обеспечивает плагин;
на iOS требуется ATS-исключение (`NSAllowsArbitraryLoads`) — см. корневой
README.md.
