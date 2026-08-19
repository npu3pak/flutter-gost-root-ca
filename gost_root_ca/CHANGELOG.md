## 0.2.0

- iOS: URLSession через прокси делегата вместо URLProtocol — конфигурация
  сессий, cookies, кэш, HTTP/2, редиректы и mTLS хост-приложения не
  затрагиваются; перехватывается только server trust challenge (схема
  как в TrustKit).
- iOS: свиззлы и встроенный корень ставятся при регистрации плагина
  (`register(with:)`), до старта Dart; оценка с якорями — на копии
  SecTrust (исходный trust не мутируется при неуспехе).
- iOS: свиззлен геттер `navigationDelegate` (identity-сравнения хоста
  работают); `PrivacyInfo.xcprivacy` подключён через resource_bundles.
- `HttpOverrides.global` больше не затирается: прежний оверрайд хоста
  становится звеном цепочки (`createHttpClient`,
  `findProxyFromEnvironment` делегируются).
- Android: убран `package=` из манифеста библиотеки (совместимость с
  AGP 8.x).
- Установлено соответствие версий: Dart `^3.8.0`, Flutter `>=3.32.0`.

## 0.1.0

- Federated-плагин `gost_root_ca`: публичное API (`GostRootCa.enable`),
  `HttpOverrides.global` для dart:io.
- Endorsed-реализации: iOS (method swizzling URLSession/WKWebView),
  Android (Network Security Config).
