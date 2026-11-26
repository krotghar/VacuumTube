import WebKit

enum WebViewRole: String {
    case browser
}

@MainActor
enum WebViewFactory {
    static func make(role: WebViewRole, coordinator: LeanbackView.Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()

        let content = config.userContentController
        content.add(coordinator, name: "vtPlayback")
        content.add(coordinator, name: "vtState")
        content.addScriptMessageHandler(SponsorFetch(), contentWorld: .page, name: "vtFetch")
        #if DEBUG
        content.add(coordinator, name: "vt")
        content.addUserScript(bundledScript("debug-probe", mainFrameOnly: true))
        #endif
        #if targetEnvironment(simulator)
        content.addUserScript(WKUserScript(
            source: "globalThis.__vtConfigOverrides = {h264ify_disable_av1: true}",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        #endif
        // The shell drags the page itself on a swipe down; touch.js then leaves that gesture alone.
        content.addUserScript(WKUserScript(source: "window.__vtNativeDrag = true", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addUserScript(bundledScript("leanback-bundle", mainFrameOnly: false))
        #if DEBUG
        if let injected = Shell.injectedScript {
            content.addUserScript(WKUserScript(source: injected, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        #endif

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Shell.userAgent
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = Shell.backgroundColor
        webView.scrollView.backgroundColor = Shell.backgroundColor
        webView.underPageBackgroundColor = Shell.backgroundColor
        webView.navigationDelegate = coordinator
        return webView
    }

    private static func bundledScript(_ name: String, mainFrameOnly: Bool) -> WKUserScript {
        let url = Bundle.main.url(forResource: name, withExtension: "js")!
        let source = try! String(contentsOf: url, encoding: .utf8)
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: mainFrameOnly)
    }
}
