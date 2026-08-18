import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Платформенный интерфейс gost_root_ca.
/// Реализации:
/// - gost_root_ca_android (Network Security Config, enable — no-op);
/// - gost_root_ca_ios (method swizzling URLSession/WKWebView).
abstract class GostRootCaPlatform extends PlatformInterface {
  GostRootCaPlatform() : super(token: _token);

  static final Object _token = Object();

  static GostRootCaPlatform _instance = MethodChannelGostRootCa();

  static GostRootCaPlatform get instance => _instance;

  static set instance(GostRootCaPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Включает поддержку корневого сертификата Минцифры
  /// на нативной стороне платформы.
  Future<void> enable(String certPem) {
    throw UnimplementedError('enable() has not been implemented.');
  }
}

/// Дефолтная реализация через MethodChannel (канал `gost_root_ca`).
class MethodChannelGostRootCa extends GostRootCaPlatform {
  static const _channel = MethodChannel('gost_root_ca');

  @override
  Future<void> enable(String certPem) async {
    await _channel.invokeMethod<void>('enable', {'certPem': certPem});
  }
}

/// Мок для тестов.
class MockGostRootCaPlatform extends GostRootCaPlatform {
  String? lastCertPem;
  int enableCallCount = 0;

  @override
  Future<void> enable(String certPem) async {
    enableCallCount++;
    lastCertPem = certPem;
  }
}
