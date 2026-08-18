import UIKit
import WebKit
import Flutter

/// Нативный WebView поверх Flutter-экрана. Статус загрузки отправляется
/// в Dart через EventChannel `gost_root_ca_example/native_webview_status`.
/// Проверка доверия покрывается прокси-свиззлом плагина gost_root_ca.
class NativeWebViewController: UIViewController, WKNavigationDelegate {
    private let url: URL
    private let eventSink: FlutterEventSink?

    private var webView: WKWebView!

    init(url: URL, eventSink: FlutterEventSink?) {
        self.url = url
        self.eventSink = eventSink
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        webView = WKWebView(frame: view.bounds)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        view.addSubview(webView)

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Закрыть", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.backgroundColor = UIColor(white: 0, alpha: 0.6)
        closeButton.layer.cornerRadius = 8
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        webView.load(URLRequest(url: url))
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sendStatus(event: "load_finished", url: webView.url?.absoluteString, error: nil)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        reportFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        reportFailure(error)
    }

    private func reportFailure(_ error: Error) {
        let nsError = error as NSError
        sendStatus(
            event: "load_failed",
            url: url.absoluteString,
            error: "\(nsError.code) \(nsError.localizedDescription)"
        )
    }

    private func sendStatus(event: String, url: String?, error: String?) {
        var payload: [String: String] = ["event": event, "url": url ?? ""]
        if let error {
            payload["error"] = error
        }
        eventSink?(payload)
    }
}
