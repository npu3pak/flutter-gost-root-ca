import 'dart:io';

import 'package:gost_root_ca/src/gost_http_overrides.dart';
import 'package:gost_root_ca/src/gost_root_ca_platform_interface.dart';
import 'package:gost_root_ca/src/gost_root_cert.dart';

export 'package:gost_root_ca/src/gost_root_ca_platform_interface.dart'
    show GostRootCaPlatform;
export 'package:gost_root_ca/src/gost_root_cert.dart' show GostRootCert;

/// Включает поддержку корневого сертификата Минцифры (Russian Trusted Root CA)
/// во всех сетевых стеках приложения:
/// - dart:io (dio, http, Image.network, cached_network_image) — через
///   HttpOverrides.global;
/// - iOS (URLSession, WKWebView) — method swizzling (см. gost_root_ca_ios);
/// - Android (WebView, HttpURLConnection) — Network Security Config
///   из gost_root_ca_android.
///
/// Идемпотентен: повторные вызовы безопасны.
class GostRootCa {
  GostRootCa._();

  /// Единственная точка входа. По умолчанию используется встроенный корень
  /// Минцифры ([GostRootCert.pem]); [certPem] позволяет передать другой.
  static Future<void> enable({String? certPem}) async {
    final pem = certPem ?? GostRootCert.pem;

    // dart:io — все HttpClient создаются с корнями платформы + корнем Минцифры.
    // Уже стоящий оверрайд приложения (прокси, логирование) не затирается,
    // а становится звеном цепочки; повторный enable() не наслаивает
    // GostHttpOverrides сам на себя.
    final current = HttpOverrides.current;
    final previous = current is GostHttpOverrides ? current.previous : current;
    HttpOverrides.global = GostHttpOverrides(certPem: pem, previous: previous);

    // Нативная сторона (iOS — свиззлинг, Android — no-op).
    await GostRootCaPlatform.instance.enable(pem);
  }
}
