## 0.2.0

- URLSession через прокси делегата вместо URLProtocol (конфигурация сессий,
  cookies, кэш, HTTP/2, редиректы, mTLS хоста не затрагиваются).
- Свиззлы и встроенный корень (`GostBuiltinRootCert`) ставятся при
  регистрации плагина, до старта Dart.
- Оценка с якорями Минцифры на копии SecTrust; свиззлен геттер
  `navigationDelegate`; `PrivacyInfo.xcprivacy` в resource_bundles.

## 0.1.0

- Endorsed-реализация gost_root_ca для iOS: method swizzling
  URLSession/WKWebView с якорями Минцифры (прокси делегата).
