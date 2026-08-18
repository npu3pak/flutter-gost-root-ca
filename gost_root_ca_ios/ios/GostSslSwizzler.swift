import Foundation
import WebKit

/// Глобальная поддержка корневого сертификата Минцифры (Russian Trusted Root CA)
/// на iOS через method swizzling:
///
/// 1. URLSession: в protocolClasses конфигураций `.default`/`.ephemeral`
///    добавляется GostSSLProtocol (URLProtocol), который оценивает серверный
///    сертификат с якорями Минцифры (механизм по мотивам netfox).
/// 2. WKWebView: navigationDelegate оборачивается в прокси-обёртку
///    (`NSObject` + `WKNavigationDelegate`), добавляющую обработку
///    server trust challenge с теми же якорями (сетевой стек WebKit
///    живёт в отдельных процессах, поэтому работает только делегатный уровень).
///
/// Единственная точка входа — `applyOnce(certPem:)` из Dart через MethodChannel
/// `gost_root_ca` (метод `enable`). Тайминг не критичен: свиззл
/// `+[NSURLSession sharedSession]`
/// возвращает сессию с GostSSLProtocol при любом обращении, а WKWebView
/// создаётся по требованию уже после вызова.
final class GostSslSwizzler {
    private static var isInstalled = false
    private static var anchorCertificates: [SecCertificate] = []

    private init() {}

    /// Единая точка входа: устанавливает оба свиззла (если ещё не сделано)
    /// и обновляет якоря Минцифры из PEM. Идемпотентна, повторные вызовы
    /// безопасны.
    static func applyOnce(certPem: String) {
        installSwizzles()
        setAnchorCertificates(certPem: certPem)
    }

    /// Устанавливает оба свиззла (идемпотентно). Якоря пока пустые —
    /// isTrusted работает как стандартная оценка доверия.
    static func installSwizzles() {
        guard !isInstalled else { return }
        isInstalled = true

        swizzleURLSessionConfiguration()
        swizzleSharedSession()
        swizzleWKWebViewNavigationDelegate()
    }

    /// Обновляет якоря Минцифры из PEM. Может вызываться несколько раз —
    /// последний вызов побеждает.
    static func setAnchorCertificates(certPem: String) {
        anchorCertificates = parseCertificates(pem: certPem)
        if anchorCertificates.isEmpty {
            NSLog("[GostTls] Не удалось распарсить сертификаты из PEM")
        }
    }

    /// Оценка доверия: сначала стандартная, при неудаче — с якорями Минцифры.
    static func isTrusted(_ trust: SecTrust) -> Bool {
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            return true
        }

        guard !anchorCertificates.isEmpty else { return false }
        SecTrustSetAnchorCertificates(trust, anchorCertificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, false)
        return SecTrustEvaluateWithError(trust, &error)
    }

    // MARK: - PEM

    private static func parseCertificates(pem: String) -> [SecCertificate] {
        let pattern = "-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let nsString = pem as NSString
        let matches = regex.matches(in: pem, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match in
            let body = nsString
                .substring(with: match.range(at: 1))
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()
            guard let data = Data(base64Encoded: body),
                  let cert = SecCertificateCreateWithData(nil, data as CFData) else {
                return nil
            }
            return cert
        }
    }

    // MARK: - Swizzling

    @discardableResult
    private static func swizzleClassMethod(_ cls: AnyClass, _ original: Selector, _ swizzled: Selector) -> Bool {
        guard let origMethod = class_getClassMethod(cls, original),
              let newMethod = class_getClassMethod(cls, swizzled) else {
            NSLog("[GostTls] Не удалось получить методы для class-swizzling \(original)")
            return false
        }
        method_exchangeImplementations(origMethod, newMethod)
        return true
    }

    @discardableResult
    private static func swizzleInstanceMethod(_ cls: AnyClass, _ original: Selector, _ swizzled: Selector) -> Bool {
        guard let origMethod = class_getInstanceMethod(cls, original),
              let newMethod = class_getInstanceMethod(cls, swizzled) else {
            NSLog("[GostTls] Не удалось получить методы для instance-swizzling \(original)")
            return false
        }
        method_exchangeImplementations(origMethod, newMethod)
        return true
    }

    private static func swizzleURLSessionConfiguration() {
        let configClass: AnyClass = object_getClass(URLSessionConfiguration.default)!

        // Дедупликация protocolClasses — GostSSLProtocol не должен добавиться дважды.
        swizzleInstanceMethod(
            configClass,
            #selector(setter: URLSessionConfiguration.protocolClasses),
            #selector(setter: URLSessionConfiguration.protocolClasses_gostSwizzled)
        )

        let sessionClass: AnyClass = object_getClass(URLSessionConfiguration.self)!
        swizzleClassMethod(
            sessionClass,
            #selector(getter: URLSessionConfiguration.default),
            #selector(getter: URLSessionConfiguration.default_gostSwizzled)
        )
        swizzleClassMethod(
            sessionClass,
            #selector(getter: URLSessionConfiguration.ephemeral),
            #selector(getter: URLSessionConfiguration.ephemeral_gostSwizzled)
        )
    }

    private static func swizzleSharedSession() {
        swizzleClassMethod(
            URLSession.self,
            #selector(getter: URLSession.shared),
            #selector(getter: URLSession.gostSharedSession)
        )
    }

    private static func swizzleWKWebViewNavigationDelegate() {
        swizzleInstanceMethod(
            WKWebView.self,
            #selector(setter: WKWebView.navigationDelegate),
            #selector(WKWebView.setNavigationDelegate_gostSwizzled(_:))
        )
    }
}

// MARK: - URLSessionConfiguration: инъекция GostSSLProtocol

@objc extension URLSessionConfiguration {
    @objc var protocolClasses_gostSwizzled: [AnyClass]? {
        get {
            return protocolClasses_gostSwizzled
        }
        set {
            guard let newTypes = newValue else {
                protocolClasses_gostSwizzled = nil
                return
            }
            var types: [AnyClass] = []
            for newType in newTypes {
                if !types.contains(where: { $0 == newType }) {
                    types.append(newType)
                }
            }
            protocolClasses_gostSwizzled = types
        }
    }

    @objc class var default_gostSwizzled: URLSessionConfiguration {
        get {
            let config = default_gostSwizzled
            config.protocolClasses?.insert(GostSSLProtocol.self, at: 0)
            return config
        }
    }

    @objc class var ephemeral_gostSwizzled: URLSessionConfiguration {
        get {
            let config = ephemeral_gostSwizzled
            config.protocolClasses?.insert(GostSSLProtocol.self, at: 0)
            return config
        }
    }
}

// MARK: - URLSession.shared: сессия с GostSSLProtocol

@objc extension URLSession {
    private static var gostSharedSessionCache: URLSession?

    /// Замена +[NSURLSession sharedSession]: возвращает сессию на основе
    /// свиззленного `.default`-конфига (с GostSSLProtocol). Даже если
    /// оригинальный sharedSession был создан до свиззлинга, наружу
    /// отдаётся наша сессия.
    @objc class var gostSharedSession: URLSession {
        get {
            if let cached = gostSharedSessionCache {
                return cached
            }
            let session = URLSession(configuration: .default)
            gostSharedSessionCache = session
            return session
        }
    }
}

// MARK: - GostSSLProtocol

@objc
private final class GostSSLProtocol: URLProtocol, URLSessionDataDelegate {
    private static let internalKey = "ru.example.gost_cert_checker.gost_ssl"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = config.protocolClasses?.filter { $0 != GostSSLProtocol.self }
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var dataTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        return canServe(request)
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest else { return false }
        return canServe(request)
    }

    private class func canServe(_ request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: internalKey, in: request) == nil,
              let scheme = request.url?.scheme?.lowercased() else {
            return false
        }
        return scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: GostSSLProtocol.internalKey, in: mutableRequest)
        dataTask = session.dataTask(with: mutableRequest as URLRequest)
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        session.invalidateAndCancel()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if GostSslSwizzler.isTrusted(serverTrust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - WKWebView: обёртка navigationDelegate

/// Обёртка над реальным navigationDelegate: добавляет обработку
/// server trust challenge с якорями Минцифры, остальные вызовы
/// пересылаются оригинальному делегату.
private final class GostNavigationDelegateProxy: NSObject, WKNavigationDelegate {
    private weak var original: AnyObject?

    init(original: AnyObject) {
        self.original = original
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(WKNavigationDelegate.webView(_:didReceive:completionHandler:)) {
            return true
        }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return original
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            if let original = original as? WKNavigationDelegate {
                original.webView?(webView, didReceive: challenge, completionHandler: completionHandler)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        if GostSslSwizzler.isTrusted(serverTrust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

@objc extension WKWebView {
    private static var gostNavigationDelegateProxyKey: UInt8 = 0

    @objc func setNavigationDelegate_gostSwizzled(_ delegate: Any?) {
        guard let delegate = delegate else {
            objc_setAssociatedObject(
                self,
                &WKWebView.gostNavigationDelegateProxyKey,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            setNavigationDelegate_gostSwizzled(nil)
            return
        }

        let proxy = GostNavigationDelegateProxy(original: delegate as AnyObject)
        objc_setAssociatedObject(
            self,
            &WKWebView.gostNavigationDelegateProxyKey,
            proxy,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        setNavigationDelegate_gostSwizzled(proxy)
    }
}
