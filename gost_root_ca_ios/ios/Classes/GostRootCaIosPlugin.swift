import Flutter
import UIKit

/// Endorsed-реализация gost_root_ca для iOS.
/// Включает method swizzling URLSession/WKWebView с якорями Минцифры
/// (см. GostSslSwizzler).
///
/// Свиззлы и встроенный корень (GostBuiltinRootCert) устанавливаются уже в
/// `register(with:)` — это происходит в `GeneratedPluginRegistrant.register`,
/// до старта Dart и до того, как другие плагины/SDK создадут свои
/// URLSession. Поэтому нативная часть работает без участия Dart;
/// `GostRootCa.enable()` нужен для dart:io (HttpOverrides) и позволяет
/// при необходимости переопределить корень своим PEM.
public class GostRootCaIosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Как можно раньше: до создания сессий другими плагинами.
    GostSslSwizzler.applyOnce(certPem: GostBuiltinRootCert.pem)

    let channel = FlutterMethodChannel(name: "gost_root_ca", binaryMessenger: registrar.messenger())
    let instance = GostRootCaIosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enable":
      guard let args = call.arguments as? [String: Any],
            let certPem = args["certPem"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "certPem is missing", details: nil))
        return
      }
      // Свиззлы уже стоят (register); здесь — только (пере)установка якоря
      // тем PEM, что пришёл из Dart (по умолчанию тот же встроенный корень).
      GostSslSwizzler.applyOnce(certPem: certPem)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
