import 'package:flutter/services.dart';
import 'package:gost_root_ca/gost_root_ca.dart';

/// Endorsed-реализация gost_root_ca для iOS:
/// нативная сторона (GostRootCaIosPlugin) делает method swizzling
/// URLSession/WKWebView с якорями Минцифры.
class GostRootCaIos extends GostRootCaPlatform {
  static const _channel = MethodChannel('gost_root_ca');

  /// Вызывается DartPluginRegistrant при старте приложения.
  static void registerWith() {
    GostRootCaPlatform.instance = GostRootCaIos();
  }

  @override
  Future<void> enable(String certPem) async {
    await _channel.invokeMethod<void>('enable', {'certPem': certPem});
  }
}
