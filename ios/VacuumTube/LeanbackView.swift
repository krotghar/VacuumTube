import SwiftUI
import WebKit

struct LeanbackView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let content = config.userContentController
        content.add(context.coordinator, name: "vt")
        content.addUserScript(Self.bundledScript("probe"))
        if Spike.touchSupport {
            content.addUserScript(Self.bundledScript("touch-flag"))
        }
        if let injected = Spike.injectedScript {
            content.addUserScript(WKUserScript(source: injected, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Spike.userAgent
        webView.allowsBackForwardNavigationGestures = false
        webView.isInspectable = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView)

        NSLog("[vt] ua=%@ touch=%@ url=%@", Spike.userAgent, String(Spike.touchSupport), Spike.startURL.absoluteString)
        webView.load(URLRequest(url: Spike.startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private static func bundledScript(_ name: String) -> WKUserScript {
        let url = Bundle.main.url(forResource: name, withExtension: "js")!
        let source = try! String(contentsOf: url, encoding: .utf8)
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private var urlObservation: NSKeyValueObservation?
        private var commandTimer: Timer?

        func attach(_ webView: WKWebView) {
            self.webView = webView
            urlObservation = webView.observe(\.url, options: [.new]) { _, change in
                let url = change.newValue??.absoluteString ?? "nil"
                Task { @MainActor in NSLog("[vt] url %@", url) }
            }
            // Spike-only remote eval: drop JS into Documents/cmd.js, result goes to the log.
            commandTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.runPendingCommand() }
            }
        }

        private func runPendingCommand() {
            guard let webView,
                  let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let file = dir.appendingPathComponent("cmd.js")
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { return }
            try? FileManager.default.removeItem(at: file)
            webView.callAsyncJavaScript(source, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    NSLog("[vt] eval ok %@", String(describing: value))
                case .failure(let error):
                    NSLog("[vt] eval error %@", String(describing: error))
                }
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            NSLog("[vt] js %@", String(describing: message.body))
        }

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

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            NSLog("[vt] content process terminated")
        }
    }
}
