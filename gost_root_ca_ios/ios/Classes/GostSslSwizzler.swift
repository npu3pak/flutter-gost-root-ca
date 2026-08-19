import Foundation
import WebKit

/// Глобальная поддержка корневого сертификата Минцифры (Russian Trusted Root CA)
/// на iOS через method swizzling:
///
/// 1. URLSession: конструкторы `+sessionWithConfiguration:` /
///    `+sessionWithConfiguration:delegate:delegateQueue:` и `+sharedSession`
///    подменяются так, что делегат каждой сессии оборачивается в прокси
///    (`GostSessionDelegateProxy`). Прокси перехватывает только server trust
///    challenge: если стандартная оценка не прошла, а с якорем Минцифры —
///    прошла, соединение пропускается; во всех остальных случаях челлендж
///    уходит оригинальному делегату (или в default handling). Сам запрос,
///    конфигурация сессии, cookies, кэш, HTTP/2, редиректы, mTLS — не трогаются.
/// 2. WKWebView: navigationDelegate оборачивается в такой же прокси
///    (сетевой стек WebKit живёт в отдельных процессах, поэтому работает
///    только делегатный уровень).
///
/// Единственная точка входа — `applyOnce(certPem:)` из Dart через MethodChannel
/// `gost_root_ca` (метод `enable`).
final class GostSslSwizzler {
    private static var isInstalled = false
    private static var anchorCertificates: [SecCertificate] = []

    private init() {}

    /// Единая точка входа: устанавливает свиззлы (если ещё не сделано)
    /// и обновляет якоря Минцифры из PEM. Идемпотентна, повторные вызовы
    /// безопасны.
    static func applyOnce(certPem: String) {
        installSwizzles()
        setAnchorCertificates(certPem: certPem)
    }

    /// Устанавливает свиззлы (идемпотентно). Якоря пока пустые —
    /// прокси ведут себя прозрачно.
    static func installSwizzles() {
        guard !isInstalled else { return }
        isInstalled = true

        swizzleURLSessionConstructors()
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

    /// true только если стандартная оценка доверия НЕ прошла, а с якорями
    /// Минцифры — прошла. Если стандартная оценка проходит, возвращает false:
    /// такие соединения плагин не трогает и отдаёт оригинальному делегату
    /// (иначе ломался бы SSL-pinning хост-приложения).
    ///
    /// Оценка с якорями делается на копии trust: если и с якорями не прошло,
    /// оригинальный делегат получает нетронутый `SecTrust`. Если копию
    /// построить нельзя — прозрачный отказ (считаем «не доверено»), чтобы
    /// никогда не оценивать с якорями trust без оригинальных политик.
    /// Якоря подставляются в исходный trust только при успехе — из него
    /// потом строится `URLCredential(trust:)`.
    static func isTrustedViaGostAnchor(_ trust: SecTrust) -> Bool {
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            return false
        }

        guard !anchorCertificates.isEmpty else { return false }

        guard let candidate = copyTrust(trust) else { return false }
        let anchors = anchorCertificates as CFArray
        SecTrustSetAnchorCertificates(candidate, anchors)
        SecTrustSetAnchorCertificatesOnly(candidate, false)
        guard SecTrustEvaluateWithError(candidate, &error) else {
            return false
        }

        SecTrustSetAnchorCertificates(trust, anchors)
        SecTrustSetAnchorCertificatesOnly(trust, false)
        return true
    }

    /// Копия trust (та же цепочка сертификатов и те же политики), чтобы не
    /// мутировать trust из челленджа при неуспешной оценке. Копия строится
    /// только с оригинальными политиками: без них (например, с default-политиками)
    /// оценка не проверяла бы hostname — поэтому возвращается nil.
    private static func copyTrust(_ trust: SecTrust) -> SecTrust? {
        let certificates: [SecCertificate]
        if #available(iOS 15.0, *) {
            certificates = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        } else {
            certificates = (0..<SecTrustGetCertificateCount(trust)).compactMap {
                SecTrustGetCertificateAtIndex(trust, $0)
            }
        }
        guard !certificates.isEmpty else { return nil }

        var policies: CFArray?
        guard SecTrustCopyPolicies(trust, &policies) == errSecSuccess,
              let policies,
              CFArrayGetCount(policies) > 0 else {
            return nil
        }

        var copy: SecTrust?
        let status = SecTrustCreateWithCertificates(certificates as CFArray, policies, &copy)
        guard status == errSecSuccess else { return nil }
        return copy
    }

    /// Server trust из челленджа, если это server trust challenge.
    static func serverTrust(of challenge: URLAuthenticationChallenge) -> SecTrust? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return nil
        }
        return challenge.protectionSpace.serverTrust
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

    /// Свиззлит оба фабричных конструктора NSURLSession. Swift-инициализаторы
    /// `URLSession(configuration:)` и `URLSession(configuration:delegate:delegateQueue:)`
    /// импортированы именно из этих class-методов.
    private static func swizzleURLSessionConstructors() {
        swizzleClassMethod(
            URLSession.self,
            NSSelectorFromString("sessionWithConfiguration:"),
            NSSelectorFromString("gost_sessionWithConfiguration:")
        )
        swizzleClassMethod(
            URLSession.self,
            NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:"),
            NSSelectorFromString("gost_sessionWithConfiguration:delegate:delegateQueue:")
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
        // Геттер отдаёт делегат хоста, а не прокси — иначе ломаются
        // identity-сравнения вида `webView.navigationDelegate === self`.
        swizzleInstanceMethod(
            WKWebView.self,
            #selector(getter: WKWebView.navigationDelegate),
            #selector(WKWebView.navigationDelegate_gostSwizzled)
        )
    }
}

// MARK: - URLSession: конструкторы с прокси-делегатом

@objc extension URLSession {
    /// Замена `+sessionWithConfiguration:` (Swift: `URLSession(configuration:)`).
    /// Сессия без делегата получает прокси с пустым оригиналом — он отвечает
    /// только на server trust challenge, всё остальное ведёт себя как без делегата.
    @objc(gost_sessionWithConfiguration:)
    class func gost_session(configuration: URLSessionConfiguration) -> URLSession {
        return gost_makeSession(configuration: configuration, delegate: nil, delegateQueue: nil)
    }

    /// Замена `+sessionWithConfiguration:delegate:delegateQueue:`
    /// (Swift: `URLSession(configuration:delegate:delegateQueue:)`).
    @objc(gost_sessionWithConfiguration:delegate:delegateQueue:)
    class func gost_session(
        configuration: URLSessionConfiguration,
        delegate: URLSessionDelegate?,
        delegateQueue: OperationQueue?
    ) -> URLSession {
        return gost_makeSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
    }

    private class func gost_makeSession(
        configuration: URLSessionConfiguration,
        delegate: URLSessionDelegate?,
        delegateQueue: OperationQueue?
    ) -> URLSession {
        let proxy = GostSessionDelegateProxy.wrap(delegate)
        // После обмена реализаций этот селектор указывает на оригинальный
        // +sessionWithConfiguration:delegate:delegateQueue:.
        return gost_session(configuration: configuration, delegate: proxy, delegateQueue: delegateQueue)
    }
}

// MARK: - URLSession.shared: сессия с прокси-делегатом

@objc extension URLSession {
    /// Ленивая инициализация `static let` потокобезопасна.
    @nonobjc private static let gostSharedSessionInstance: URLSession = {
        // Идёт через свиззленный конструктор — делегат-прокси подставится сам.
        return URLSession(configuration: .default)
    }()

    /// Замена `+[NSURLSession sharedSession]`: у настоящей shared-сессии
    /// делегата нет и добавить его нельзя, поэтому наружу отдаётся своя
    /// сессия на `.default`-конфиге с прокси-делегатом.
    @objc class var gostSharedSession: URLSession {
        return gostSharedSessionInstance
    }
}

// MARK: - URLSession: прокси делегата

/// Обёртка над делегатом URLSession. Перехватывает только server trust
/// challenge (на уровне сессии и на уровне задачи), остальные вызовы
/// прозрачно уходят оригинальному делегату через forwarding.
///
/// Схема ответа на `respondsToSelector:` повторяет TrustKit:
/// - task-level challenge — всегда YES: если у оригинала нет session-level
///   метода, Foundation доставит server trust сюда;
/// - session-level challenge — YES только если его реализует оригинал:
///   тогда Foundation доставит server trust сюда, а мы перешлём оригиналу.
/// Так перехват гарантирован в обоих случаях, а оригинал получает ровно те
/// вызовы, на которые подписан.
///
/// Оригинал удерживается сильно: URLSession удерживает свой делегат сильно
/// до invalidate, и семантика для хоста должна сохраниться (частый паттерн —
/// `URLSession(configuration:delegate: Handler(), delegateQueue:)` без
/// других ссылок на Handler).
private final class GostSessionDelegateProxy: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private static let sessionChallengeSelector =
        NSSelectorFromString("URLSession:didReceiveChallenge:completionHandler:")
    private static let taskChallengeSelector =
        NSSelectorFromString("URLSession:task:didReceiveChallenge:completionHandler:")

    let original: URLSessionDelegate?

    private init(original: URLSessionDelegate?) {
        self.original = original
    }

    /// Оборачивает делегат; уже обёрнутый не оборачивает повторно
    /// (`+sessionWithConfiguration:` внутри может вызывать трёхаргументный
    /// конструктор — иначе получили бы прокси над прокси).
    static func wrap(_ delegate: URLSessionDelegate?) -> URLSessionDelegate {
        if let proxy = delegate as? GostSessionDelegateProxy {
            return proxy
        }
        return GostSessionDelegateProxy(original: delegate)
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == GostSessionDelegateProxy.taskChallengeSelector {
            return true
        }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return original
    }

    override func conforms(to aProtocol: Protocol) -> Bool {
        if super.conforms(to: aProtocol) {
            return true
        }
        return original?.conforms(to: aProtocol) ?? false
    }

    // MARK: session-level challenge

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let trust = GostSslSwizzler.serverTrust(of: challenge),
           GostSslSwizzler.isTrustedViaGostAnchor(trust) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        if let original = original,
           original.responds(to: GostSessionDelegateProxy.sessionChallengeSelector) {
            original.urlSession?(session, didReceive: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: task-level challenge

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let trust = GostSslSwizzler.serverTrust(of: challenge),
           GostSslSwizzler.isTrustedViaGostAnchor(trust) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        if let original = original as? URLSessionTaskDelegate,
           original.responds(to: GostSessionDelegateProxy.taskChallengeSelector) {
            original.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - WKWebView: обёртка navigationDelegate

/// Обёртка над реальным navigationDelegate: добавляет обработку
/// server trust challenge с якорями Минцифры, остальные вызовы
/// пересылаются оригинальному делегату. Оригинал удерживается слабо —
/// как и сам `WKWebView.navigationDelegate`.
private final class GostNavigationDelegateProxy: NSObject, WKNavigationDelegate {
    private(set) weak var original: AnyObject?

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
        if let trust = GostSslSwizzler.serverTrust(of: challenge),
           GostSslSwizzler.isTrustedViaGostAnchor(trust) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        if let original = original as? WKNavigationDelegate,
           original.responds(to: #selector(WKNavigationDelegate.webView(_:didReceive:completionHandler:))) {
            original.webView?(webView, didReceive: challenge, completionHandler: completionHandler)
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

    /// Замена геттера `navigationDelegate`: если внутри стоит наш прокси —
    /// возвращаем делегат хоста, как он его и ставил.
    @objc func navigationDelegate_gostSwizzled() -> WKNavigationDelegate? {
        // После обмена реализаций этот вызов — оригинальный геттер.
        let current = navigationDelegate_gostSwizzled()
        if let proxy = current as? GostNavigationDelegateProxy {
            return proxy.original as? WKNavigationDelegate
        }
        return current
    }
}
