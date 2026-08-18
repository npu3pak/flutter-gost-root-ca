# gost_root_ca

Поддержка корневого сертификата НУЦ Минцифры России (**Russian Trusted Root CA**)
во всех сетевых стеках Flutter-приложения: гостовские сайты (например,
www.sberbank.ru) перестают падать с ошибками проверки сертификата.

## Структура

| Каталог | Содержимое |
|---|---|
| `gost_root_ca/` | корневой пакет: публичное API, `HttpOverrides.global` для dart:io, PEM-константа |
| `gost_root_ca_ios/` | endorsed iOS: method swizzling `URLSession`/`WKWebView` (якоря SecTrust) |
| `gost_root_ca_android/` | endorsed Android: Network Security Config (системные корни + корень Минцифры) |
| `example/` | тестовое приложение: 5 поверхностей × 2 URL (yandex/sber) |

## Интеграция

1. Добавьте зависимость в `pubspec.yaml`:
   ```yaml
   gost_root_ca:
     path: plugins/gost_root_ca/gost_root_ca
   ```
2. Вызовите один раз при старте приложения:
   ```dart
   import 'package:gost_root_ca/gost_root_ca.dart';

   void main() {
     WidgetsFlutterBinding.ensureInitialized();
     GostRootCa.enable();
     runApp(const MyApp());
   }
   ```
3. **iOS:** добавьте в `ios/Runner/Info.plist` (обязательно — плагин не может
   редактировать Info.plist хоста):
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsArbitraryLoads</key>
       <true/>
   </dict>
   ```
   Без этого ATS блокирует соединения с цепочками НУЦ Минцифры
   (проявляется как `-1202` в WKWebView).

Это всё. Android-конфигурация (Network Security Config с корнем Минцифры)
приходит из плагина автоматически.

## Если у вас уже есть свой `networkSecurityConfig` (Android)

Плагин подключает свой конфиг через манифест. Если в проекте уже объявлен
свой `networkSecurityConfig` — возникает конфликт мерджера, а содержимое
конфигов **не объединяется автоматически**: ваш конфиг заменяет конфиг
плагина, поэтому корень Минцифры нужно добавить в него вручную.

**1. Положите сертификат в свой проект.**

Скопируйте корневой сертификат Минцифры (тот же PEM-текст, что в
`gost_root_ca/gost_root_ca/lib/src/gost_root_cert.dart`) в:

```
android/app/src/main/res/raw/russian_trusted_root_ca.pem
```

Готовый файл можно взять из плагина:
`plugins/gost_root_ca/gost_root_ca_android/android/src/main/res/raw/gost_russian_trusted_root_ca.pem`

**2. Дополните свой конфиг** — `android/app/src/main/res/xml/network_security_config.xml`.

В блок `<trust-anchors>` добавьте строку:

```xml
<certificates src="@raw/russian_trusted_root_ca" />
```

Итоговый конфиг:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config>
        <trust-anchors>
            <certificates src="system" />
            <certificates src="@raw/russian_trusted_root_ca" />
        </trust-anchors>
    </base-config>
</network-security-config>
```

**3. Подключите в манифесте** — `android/app/src/main/AndroidManifest.xml`
(`tools:replace` снимает конфликт с атрибутом плагина):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application
        android:networkSecurityConfig="@xml/network_security_config"
        tools:replace="android:networkSecurityConfig"
        ...>
```

*Альтернатива:* можно сослаться на ресурс плагина напрямую —
`@raw/gost_russian_trusted_root_ca` (ресурсы AAR доступны хосту, проверено
по merged-ресурсам). Но собственная копия в проекте надёжнее: не зависит
от внутренних имён плагина.

## API

```dart
Future<void> GostRootCa.enable({String? certPem});
```

- По умолчанию используется встроенный корень Минцифры
  (`GostRootCert.pem`).
- Идемпотентен: повторные вызовы безопасны.

## Сертификат

Корень хранится в **двух** местах (обновлять оба при ротации):

1. `gost_root_ca/gost_root_ca/lib/src/gost_root_cert.dart` — dart:io
   (HttpOverrides) и iOS (через канал);
2. `gost_root_ca/gost_root_ca_android/android/src/main/res/raw/gost_russian_trusted_root_ca.pem`
   — Android Network Security Config.

Источник сертификата: https://www.gosuslugi.ru/crt

## Ограничения

- **iOS background-сессии** (`URLSessionConfiguration.background`) —
  `URLProtocol` с ними официально несовместим (документация Apple),
  фоновые запросы выполняет системный демон. Варианты: делегат сессии
  с якорями Минцифры (работает, пока приложение живо; в суспенде — риск
  таймаутов), установленный на устройстве профиль с корнем, либо
  обычная сессия / dart:io (`HttpOverrides`).
- **SFSafariViewController / Chrome Custom Tabs** — системные браузеры в
  отдельных процессах; нужен установленный на устройстве корень.
- **`URLSessionConfiguration()`** (plain init, iOS) — невалидный путь:
  крэшит создание сессии, не поддерживается. Конфиги — только через
  `.default`/`.ephemeral`/`.background`.
- Плагинные/нативные сессии, созданные **до** первого вызова
  `GostRootCa.enable()`, на iOS не получают протокол (стандартные CA
  работают и без него).
