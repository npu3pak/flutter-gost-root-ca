import 'dart:convert';
import 'dart:io';

import 'package:gost_root_ca/src/gost_root_cert.dart';

/// Глобальный оверрайд dart:io HttpClient: доверенные корни платформы
/// (стандартный SSL) + корневой сертификат Минцифры (Russian Trusted Root CA)
/// для гостовских цепочек.
///
/// HttpOverrides.global применяется ко всем HttpClient, создаваемым через
/// фабрику HttpClient(): dio, http, Image.network, cached_network_image
/// и т.д. — переопределять клиент у каждой библиотеки не нужно.
///
/// Не затирает уже установленный оверрайд приложения: если передан
/// [previous] (обычно — `HttpOverrides.current` на момент включения),
/// создание клиента и `findProxyFromEnvironment` делегируются ему, а наш
/// [SecurityContext] подставляется как контекст по умолчанию. Так прокси/
/// логирование хоста и корень Минцифры работают одновременно.
///
/// Если гостовский корень не удалось добавить в хранилище,
/// стандартный SSL продолжает работать.
class GostHttpOverrides extends HttpOverrides {
  final String certPem;

  /// Оверрайд, стоявший до нас; `null` — цепочки нет, используется
  /// поведение по умолчанию.
  final HttpOverrides? previous;

  GostHttpOverrides({
    String? certPem,
    this.previous,
  }) : certPem = certPem ?? GostRootCert.pem;

  static SecurityContext? _securityContext;
  static String? _securityContextPem;

  /// Создаёт HttpClient с единым хранилищем доверенных корней:
  /// корни платформы + корень Минцифры (если PEM удалось добавить
  /// в хранилище). Явно переданный [context] уважается — наш
  /// подставляется только вместо `null`.
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final effective = context ?? _getSecurityContext();
    final prev = previous;
    if (prev != null) {
      return prev.createHttpClient(effective);
    }
    return super.createHttpClient(effective);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    final prev = previous;
    if (prev != null) {
      return prev.findProxyFromEnvironment(url, environment);
    }
    return super.findProxyFromEnvironment(url, environment);
  }

  SecurityContext _getSecurityContext() {
    if (_securityContext == null || _securityContextPem != certPem) {
      _securityContext = _buildSecurityContext();
      _securityContextPem = certPem;
    }
    return _securityContext!;
  }

  SecurityContext _buildSecurityContext() {
    final context = SecurityContext(withTrustedRoots: true);
    try {
      context.setTrustedCertificatesBytes(utf8.encode(certPem));
    } catch (_) {
      // Стандартный SSL продолжает работать без корня Минцифры.
    }

    return context;
  }
}
