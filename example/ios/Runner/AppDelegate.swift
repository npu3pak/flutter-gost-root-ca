import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var webViewStatusSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let registrar = self.registrar(forPlugin: "gost_root_ca_example_native") {
      setupNativeTlsTestChannel(registrar: registrar)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupNativeTlsTestChannel(registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()

    let methodChannel = FlutterMethodChannel(
      name: "gost_root_ca_example/native_tls_test",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "checkUrl":
        guard let args = call.arguments as? [String: Any],
              let url = args["url"] as? String else {
          result(FlutterError(code: "invalid_arguments", message: "url is missing", details: nil))
          return
        }
        self.checkUrl(url, completion: result)
      case "openNativeWebView":
        guard let args = call.arguments as? [String: Any],
              let url = args["url"] as? String else {
          result(FlutterError(code: "invalid_arguments", message: "url is missing", details: nil))
          return
        }
        self.openNativeWebView(url, completion: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: "gost_root_ca_example/native_webview_status",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
  }

  private func checkUrl(_ urlString: String, completion: @escaping FlutterResult) {
    guard let url = URL(string: urlString) else {
      completion(FlutterError(code: "invalid_url", message: urlString, details: nil))
      return
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 30

    // Свиззл +[NSURLSession sharedSession] выполнен плагином gost_root_ca
    // при старте Dart — доступ к URLSession.shared возвращает сессию
    // с прокси-делегатом, обрабатывающим server trust с якорем Минцифры.
    URLSession.shared.dataTask(with: request) { _, response, error in
      var map: [String: Any] = ["success": error == nil]
      if let http = response as? HTTPURLResponse {
        map["statusCode"] = http.statusCode
      }
      if let error = error {
        map["error"] = "\(error)"
      }
      completion(map)
    }.resume()
  }

  private func openNativeWebView(_ urlString: String, completion: @escaping FlutterResult) {
    guard let url = URL(string: urlString) else {
      completion(FlutterError(code: "invalid_url", message: urlString, details: nil))
      return
    }
    guard let rootViewController = topViewController() else {
      completion(false)
      return
    }

    let webViewController = NativeWebViewController(url: url, eventSink: webViewStatusSink)
    webViewController.modalPresentationStyle = .fullScreen
    rootViewController.present(webViewController, animated: true) {
      completion(true)
    }
  }

  /// Корневой контроллер для презентации нативного WebView.
  /// Scene-based шаблон (UIApplicationSceneManifest) не заполняет
  /// AppDelegate.window — окно живёт в UIWindowScene, поэтому сначала
  /// ищем там, затем fallback на классический window.
  private func topViewController() -> UIViewController? {
    if let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }),
      let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
      return root
    }
    return window?.rootViewController
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    webViewStatusSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    webViewStatusSink = nil
    return nil
  }
}
