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
/// Если гостовский корень не удалось добавить в хранилище,
/// стандартный SSL продолжает работать.
class GostHttpOverrides extends HttpOverrides {
  final String certPem;

  GostHttpOverrides({
    String? certPem,
  }) : certPem = certPem ?? GostRootCert.pem;

  static SecurityContext? _securityContext;
  static String? _securityContextPem;

  /// Создаёт HttpClient с единым хранилищем доверенных корней:
  /// корни платформы + корень Минцифры (если он прошёл проверку).
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context ?? _getSecurityContext());
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
