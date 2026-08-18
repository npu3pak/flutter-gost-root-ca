import Flutter
import UIKit

/// Endorsed-реализация gost_root_ca для iOS.
/// Включает method swizzling URLSession/WKWebView с якорями Минцифры
/// (см. GostSslSwizzler).
public class GostRootCaIosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
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
      GostSslSwizzler.applyOnce(certPem: certPem)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
