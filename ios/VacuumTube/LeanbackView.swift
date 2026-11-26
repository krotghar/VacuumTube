import SwiftUI
import WebKit

struct LeanbackView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()

        let content = config.userContentController
        content.add(context.coordinator, name: "vtPlayback")
        #if DEBUG
        content.add(context.coordinator, name: "vt")
        content.addUserScript(Self.bundledScript("debug-probe", mainFrameOnly: true))
        #endif
        #if targetEnvironment(simulator)
        content.addUserScript(WKUserScript(
            source: "globalThis.__vtConfigOverrides = {h264ify_disable_av1: true}",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        #endif
        content.addUserScript(Self.bundledScript("leanback-bundle", mainFrameOnly: false))
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
        webView.navigationDelegate = context.coordinator
        // Touches starting on these strips never reach the page, so the back swipe cannot scroll a shelf or tap the rail.
        for leftEdge in [true, false] {
            let strip = UIView(frame: CGRect(x: leftEdge ? 0 : -20, y: 0, width: 20, height: 0))
            strip.autoresizingMask = leftEdge ? [.flexibleHeight, .flexibleRightMargin] : [.flexibleHeight, .flexibleLeftMargin]
            strip.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.backSwipe(_:))))
            webView.addSubview(strip)
        }
        context.coordinator.attach(webView)

        #if DEBUG
        NSLog("[vt] ua=%@ url=%@", Shell.userAgent, Shell.startURL.absoluteString)
        #endif
        webView.load(URLRequest(url: Shell.startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private static func bundledScript(_ name: String, mainFrameOnly: Bool) -> WKUserScript {
        let url = Bundle.main.url(forResource: name, withExtension: "js")!
        let source = try! String(contentsOf: url, encoding: .utf8)
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: mainFrameOnly)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        #if DEBUG
        weak var webView: WKWebView?
        var urlObservation: NSKeyValueObservation?
        var commandTimer: Timer?
        #endif

        func attach(_ webView: WKWebView) {
            #if DEBUG
            self.webView = webView
            startDebugTools(for: webView)
            #endif
        }

        @objc func backSwipe(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended, let strip = gesture.view, let webView = strip.superview as? WKWebView else { return }
            let inward = strip.frame.minX < webView.bounds.midX ? 1.0 : -1.0
            guard gesture.translation(in: webView).x * inward > 60 else { return }
            webView.evaluateJavaScript("window.__vtBack?.()")
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "vtPlayback" {
                let playing = (message.body as? Bool) ?? false
                UIApplication.shared.isIdleTimerDisabled = playing
                #if DEBUG
                NSLog("[vt] idle disabled=%@", String(playing))
                #endif
                return
            }
            #if DEBUG
            NSLog("[vt] js %@", String(describing: message.body))
            #endif
        }

        #if DEBUG
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
                NSLog("[vt] main frame %ld %@", http.statusCode, http.url?.absoluteString ?? "")
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("[vt] didFail %@", String(describing: error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("[vt] didFailProvisional %@", String(describing: error))
        }
        #endif

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            UIApplication.shared.isIdleTimerDisabled = false
            #if DEBUG
            NSLog("[vt] content process terminated")
            #endif
        }
    }
}
