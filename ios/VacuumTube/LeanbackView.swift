import os
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
        content.addScriptMessageHandler(SponsorFetch(), contentWorld: .page, name: "vtFetch")
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
        // Right edge only: Stage Manager owns the left edge and does not defer it.
        let strip = UIView(frame: CGRect(x: -20, y: 0, width: 20, height: 0))
        strip.autoresizingMask = [.flexibleHeight, .flexibleLeftMargin]
        strip.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.backSwipe(_:))))
        webView.addSubview(strip)
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
        // Role of the web view in logs; the mini player will get its own coordinator.
        let role = "browser"
        weak var webView: WKWebView?
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.krotghar.VacuumTube", category: "webview")
        private var terminations: [Date] = []
        private var pendingReload = false
        private var placeholder: UIView?
        private var activeObserver: NSObjectProtocol?
        #if DEBUG
        var urlObservation: NSKeyValueObservation?
        var commandTimer: Timer?
        #endif

        func attach(_ webView: WKWebView) {
            self.webView = webView
            activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.pendingReload else { return }
                    self.pendingReload = false
                    self.reloadPage()
                }
            }
            #if DEBUG
            startDebugTools(for: webView)
            #endif
        }

        private func reloadPage() {
            guard let webView else { return }
            if webView.url != nil { webView.reload() } else { webView.load(URLRequest(url: Shell.startURL)) }
        }

        private func showPlaceholder(in webView: WKWebView) {
            guard placeholder == nil else { return }
            let view = UIView(frame: webView.bounds)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.backgroundColor = Shell.backgroundColor

            let label = UILabel()
            label.text = "Страница перестала отвечать"
            label.textColor = .white
            label.font = .preferredFont(forTextStyle: .title2)

            var config = UIButton.Configuration.filled()
            config.title = "Перезагрузить"
            let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
                self?.restore()
            })

            let stack = UIStackView(arrangedSubviews: [label, button])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 24
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            webView.addSubview(view)
            placeholder = view
        }

        private func restore() {
            terminations.removeAll()
            placeholder?.removeFromSuperview()
            placeholder = nil
            reloadPage()
        }

        @objc func backSwipe(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended, let webView = gesture.view?.superview as? WKWebView else { return }
            guard gesture.translation(in: webView).x < -60 else { return }
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
            let now = Date()
            terminations = terminations.filter { now.timeIntervalSince($0) < 120 } + [now]
            let reload = terminations.count <= 3
            let url = webView.url
            let route = (url?.fragment).map { String($0.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") } ?? "-"
            logger.error("WebContent terminated role=\(self.role, privacy: .public) count=\(self.terminations.count, privacy: .public) route=\(route, privacy: .public) reload=\(reload, privacy: .public) url=\(url?.absoluteString ?? "-", privacy: .private)")
            guard reload else {
                showPlaceholder(in: webView)
                return
            }
            if UIApplication.shared.applicationState == .active {
                reloadPage()
            } else {
                pendingReload = true
            }
        }
    }
}
