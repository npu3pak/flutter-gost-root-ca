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

## Требования

- Dart `^3.8.0`, Flutter `>=3.32.0`;
- iOS 13+ (podspec `gost_root_ca_ios`);
- Android minSdk 24.

## Интеграция

1. Добавьте зависимость в `pubspec.yaml` — локально, из корня репозитория:

   ```yaml
   gost_root_ca:
     path: gost_root_ca
   ```

   Если репозиторий вложен в `plugins/` родительского проекта, путь
   будет `plugins/gost_root_ca/gost_root_ca`; с GitHub — так:

   ```yaml
   gost_root_ca:
     git:
       url: https://github.com/npu3pak/flutter-gost-root-ca.git
       path: gost_root_ca
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
   Без ATS-исключения соединения с цепочками НУЦ Минцифры блокируются
   (`-1200/-9802` в URLSession, `-1202` в WKWebView). Глобальный
   `NSAllowsArbitraryLoads` — единственный подтверждённый вариант; почему
   более узкие исключения не подходят — см. раздел «ATS (iOS)».

Это всё. Android-конфигурация (Network Security Config с корнем Минцифры)
приходит из плагина автоматически.

### Если у вас уже есть свой `networkSecurityConfig` (Android)

Плагин подключает свой конфиг через манифест. Если в проекте уже объявлен
свой `networkSecurityConfig` — возникает конфликт мерджера, а содержимое
конфигов **не объединяется автоматически**: ваш конфиг заменяет конфиг
плагина, поэтому корень Минцифры нужно добавить в него вручную.

**1. Положите сертификат в свой проект.**

Скопируйте корневой сертификат Минцифры (тот же PEM-текст, что в
`gost_root_ca/lib/src/gost_root_cert.dart`) в:

```
android/app/src/main/res/raw/russian_trusted_root_ca.pem
```

Готовый файл можно взять из плагина:
`gost_root_ca_android/android/src/main/res/raw/gost_russian_trusted_root_ca.pem`

**2. Дополните свой конфиг** — `android/app/src/main/res/xml/network_security_config.xml`.

В блок `<trust-anchors>` добавьте строку:

```xml
<certificates src="@raw/russian_trusted_root_ca" />
```

Пример итогового конфига:

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
`@raw/gost_russian_trusted_root_ca` (ресурсы AAR-зависимости попадают
в приложение при мердже ресурсов и доступны по своему имени). Но
собственная копия в проекте надёжнее: не зависит от внутренних имён
плагина.

## Описание технического решения

### В чём проблема

Когда приложение открывает https-страницу или делает https-запрос, устройство
проверяет сертификат сайта: он должен быть выпущен одним из «доверенных
корневых центров» (CA), список которых встроен в систему. Сайты с гостовской
поддержкой — например, www.sberbank.ru — используют корень **НУЦ Минцифры
России (Russian Trusted Root CA)**, которого в системных списках нет. Поэтому
устройство не может подтвердить подлинность соединения и обрывает его:
пользователь видит «сертификат недействителен», в логах — ошибку `-1202`
(на iOS) или `ERR_CERT_AUTHORITY_INVALID` (на Android). Обычный SSL
(яндекс, гугл) работает, потому что их корни в системе есть.

### Что делает плагин

Плагин «подкладывает» корень Минцифры во **все** места, где приложение
проверяет сертификаты. Проверка при этом не отключается: сначала сертификат
оценивается как обычно (системные корни), и только если стандартная проверка
не прошла — добавляется корень Минцифры и оценка повторяется. Подделать
соединение сложнее не становится: цепочка должна доходить до настоящего
корня Минцифры.

### Почему механизмов несколько

В приложении сеть ходит разными путями, и у каждого пути **своя** проверка
сертификатов. Плагин настраивает каждый путь отдельно:

| Поверхность | Где проверяется сертификат | Чем настраивает плагин |
|---|---|---|
| REST на Flutter-стороне (dio, http) | движок dart:io (общий для iOS и Android) | `HttpOverrides.global` |
| Изображения (`Image.network`, cached_network_image) | тот же dart:io | `HttpOverrides.global` |
| REST на нативной стороне (iOS `URLSession`) | системный сетевой стек | method swizzling: прокси делегата сессии |
| REST на нативной стороне (Android `HttpURLConnection`) | системный стек Android | Network Security Config |
| WebView на Flutter-стороне (webview_flutter) | iOS: `WKWebView`; Android: системный WebView | iOS — прокси делегата; Android — NSC |
| WebView на нативном экране | то же самое | то же самое |

### 1. Flutter-стек: dart:io (обе платформы)

Всё, что делает Flutter-код через `HttpClient` (а это dio, http-пакет,
`Image.network`, `cached_network_image`), идёт через движок dart:io — он
работает одинаково на iOS и Android. Плагин один раз устанавливает
`HttpOverrides.global` — глобальную фабрику `HttpClient`: через неё
создаются все HTTP-клиенты приложения. В его списке доверия — системные
корни **плюс** корень Минцифры. Поэтому отдельно настраивать dio, http
или картинки не нужно: достаточно одного вызова `GostRootCa.enable()`.

Если в приложении уже стоит свой `HttpOverrides.global` (дебаг-прокси,
логирование), плагин его не затирает: прежний оверрайд становится звеном
цепочки — ему делегируются создание клиента и `findProxyFromEnvironment`,
а контекст с корнем Минцифры подставляется вместо `null`. Повторный
`enable()` не наслаивает оверрайд сам на себя.

### 2. iOS: нативные стеки

#### URLSession (нативный REST и HTTP-запросы плагинов)

У Apple нет способа «просто добавить корень глобально». Поэтому плагин
применяет **method swizzling** — официально разрешённую технику подмены
системных методов на этапе выполнения:
- конструкторы сессий (`+sessionWithConfiguration:`,
  `+sessionWithConfiguration:delegate:delegateQueue:`) и сам
  `+[NSURLSession sharedSession]` подменяются так, что делегат **каждой**
  создаваемой сессии оборачивается в прокси (по той же схеме, что в
  TrustKit); сессия без делегата получает прокси с пустым оригиналом;
- прокси перехватывает **только** server trust challenge: сначала
  сертификат оценивается стандартно; если не прошло — добавляется корень
  Минцифры в якоря (`SecTrustSetAnchorCertificates`) и оценка повторяется;
- если цепочка сходится к корню Минцифры — соединение пропускается
  (`useCredential`); во всех остальных случаях (стандартная оценка прошла,
  не прошла даже с якорем, не-trust челлендж — Basic auth, client cert)
  вызов **уходит оригинальному делегату** или в default handling, как и
  без плагина. Поэтому SSL-pinning и mTLS хост-приложения продолжают
  работать.

Сам запрос при этом не переигрывается: конфигурация сессии, cookies, кэш,
прокси, HTTP/2, редиректы, метрики — остаются как есть.

#### WKWebView (WebView Flutter и нативный WebView)

Сетевой стек WebKit работает **в отдельных системных процессах** — туда
перехватчик запросов не дотягивается. Доступен только делегатный уровень:
WebView сообщает приложению «сертификат не подошёл» и спрашивает, что делать.
Плагин свиззлит `setNavigationDelegate:` — метод установки делегата — и
оборачивает любой делегат в прокси, который на этот вопрос отвечает:
«проверь ещё раз с корнем Минцифры; если сходится — пропусти». Работает для
любых WebView, включая созданные внутри `webview_flutter` и на нативных
экранах.

#### ATS (iOS)

Дополнительно Apple требует «политику безопасного соединения» (ATS).
Помимо TLS 1.2+/PFS/размера ключа, ATS требует, чтобы цепочка сходилась к
корню, встроенному в ОС или установленному пользователем/MDM; якоря,
подставленные через `SecTrustSetAnchorCertificates`, ATS не учитывает.
Поэтому без исключения в Info.plist соединения с цепочками Минцифры
блокируются ещё **до** проверки доверия — ATS-исключение обязательно.
Подтверждено на устройстве.

Единственный подтверждённый вариант — глобальный `NSAllowsArbitraryLoads`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

Более узкие варианты (`NSExceptionDomains`, `NSAllowsArbitraryLoadsInWebContent`)
для цепочек НУЦ Минцифры **не работают** (проверено на устройстве): ATS-
исключения для доменов не отключают проверку корня для HTTPS, а
`NSExceptionAllowsInsecureHTTPLoads` относится только к HTTP-загрузкам.
dart:io (dio, http, картинки) эти ключи не затрагивают вообще.

Example-приложение использует глобальный `NSAllowsArbitraryLoads`, потому
что тестирует все поверхности на произвольных хостах.

#### Как включается

Свиззлы и встроенный корень (`GostBuiltinRootCert.swift`) ставятся уже при
регистрации плагина — в `GeneratedPluginRegistrant.register`, до старта Dart
и до того, как другие плагины/SDK создадут свои `URLSession`. Поэтому
нативная часть на iOS работает сама по себе, без ожидания Dart.
`GostRootCa.enable()` нужен для dart:io (`HttpOverrides`) и, если передан
свой `certPem`, переопределяет корень на нативной стороне через
MethodChannel `gost_root_ca`. Никакого нативного кода в хост-приложении
не требуется.

### 3. Android: нативные стеки (Network Security Config)

Android решает ту же задачу декларативно, без рантайм-кода: существует
официальный файл **Network Security Config**, который задаёт доверенные
корни для всех нативных сетевых стеков приложения (WebView, в том числе
внутри `webview_flutter`, `HttpURLConnection`, OkHttp). Плагин кладёт такой
файл («системные корни + корень Минцифры») в свой Android-пакет и прописывает
ссылку на него в своём манифесте; при сборке приложения атрибут
автоматически вливается в `<application>` хоста. Если в проекте уже есть
собственный Network Security Config — он побеждает, и корень нужно добавить
в него вручную (см. раздел «Если у вас уже есть свой networkSecurityConfig»).

dart:io-часть (REST Flutter, изображения) на Android работает так же, как в
п. 1.

## Ограничения (что не покрывается)

- **iOS background-сессии** (`URLSessionConfiguration.background`) —
  прокси-делегат работает, пока приложение живо (челлендж доставляется
  делегату); если задача выполняется системным демоном в суспенде —
  риск таймаута. Варианты: установленный на устройстве профиль с корнем,
  либо обычная сессия / dart:io (`HttpOverrides`).
- **SFSafariViewController / Chrome Custom Tabs** — системные браузеры в
  отдельных процессах; нужен установленный на устройстве корень.
- **Task-specific делегаты (iOS 15+)** — если у задачи задан свой
  `task.delegate` (или используется `URLSession.data(for:delegate:)`) и он
  сам реализует `urlSession(_:task:didReceive:completionHandler:)`, server
  trust уходит ему, минуя прокси сессии. Такому делегату нужно вызвать
  оценку с якорем самостоятельно.
- Нативные сессии, созданные **до** регистрации плагинов
  (`GeneratedPluginRegistrant.register`) — например, в `+load` или в
  статиках нативного кода до `didFinishLaunching`, — на iOS не покрываются
  (стандартные CA работают и без плагина). Всё, что создаётся после
  регистрации, покрыто независимо от того, когда и был ли вызван
  `GostRootCa.enable()`.

## API

```dart
Future<void> GostRootCa.enable({String? certPem});
```

- По умолчанию используется встроенный корень Минцифры
  (`GostRootCert.pem`).
- Идемпотентен: повторные вызовы безопасны.

## Сертификат

Сертификат в плагине хранится в **трёх** местах (обновлять все при ротации):

1. `gost_root_ca/lib/src/gost_root_cert.dart` — dart:io
   (HttpOverrides) и значение по умолчанию для `enable()`;
2. `gost_root_ca_ios/ios/Classes/GostBuiltinRootCert.swift` — iOS,
   встроенный корень, ставится при регистрации плагина;
3. `gost_root_ca_android/android/src/main/res/raw/gost_russian_trusted_root_ca.pem`
   — Android Network Security Config.

Источник сертификата: https://www.gosuslugi.ru/crt

