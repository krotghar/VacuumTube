import os
import SwiftUI
import WebKit

struct LeanbackView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(role: .browser) }

    func makeUIView(context: Context) -> ShellView {
        let coordinator = context.coordinator
        let webView = WebViewFactory.make(role: .browser, coordinator: coordinator)
        coordinator.attach(webView)

        #if DEBUG
        NSLog("[vt:browser] ua=%@ url=%@", Shell.userAgent, Shell.startURL.absoluteString)
        #endif
        webView.load(URLRequest(url: Shell.startURL))
        return ShellView(webView: webView, coordinator: coordinator)
    }

    func updateUIView(_ shell: ShellView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let role: WebViewRole
        var state = PageState()
        weak var webView: WKWebView?
        /// What the page asked of the shell through `vtRoute`.
        var onRoute: (@MainActor ([String: Any]) -> Void)?
        var onDidCommit: (@MainActor () -> Void)?
        var onDidFinish: (@MainActor () -> Void)?
        var onTerminate: (@MainActor () -> Void)?
        var onStateChange: (@MainActor () -> Void)?
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.krotghar.VacuumTube", category: "webview")
        private var terminations: [Date] = []
        private var pendingReload = false
        private var placeholder: UIView?
        private var activeObserver: NSObjectProtocol?
        #if DEBUG
        var urlObservation: NSKeyValueObservation?
        var commandTimer: Timer?
        #endif

        init(role: WebViewRole) {
            self.role = role
        }

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

        func reloadPage() {
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

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "vtPlayback" {
                let playing = (message.body as? Bool) ?? false
                PlaybackTracker.set(role, playing: playing)
                #if DEBUG
                NSLog("[vt:%@] playing=%@ idle disabled=%@", role.rawValue, String(playing), String(UIApplication.shared.isIdleTimerDisabled))
                #endif
                return
            }
            if message.name == "vtRoute" {
                if let body = message.body as? [String: Any] { onRoute?(body) }
                return
            }
            if message.name == "vtState" {
                state = PageState(message.body as? [String: Any] ?? [:])
                onStateChange?()
                return
            }
            #if DEBUG
            NSLog("[vt:%@] js %@", role.rawValue, String(describing: message.body))
            #endif
        }

        #if DEBUG
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            if navigationResponse.isForMainFrame, let http = navigationResponse.response as? HTTPURLResponse {
                NSLog("[vt:%@] main frame %ld %@", role.rawValue, http.statusCode, http.url?.absoluteString ?? "")
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("[vt:%@] didFail %@", role.rawValue, String(describing: error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("[vt:%@] didFailProvisional %@", role.rawValue, String(describing: error))
        }
        #endif

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onDidCommit?()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onDidFinish?()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            PlaybackTracker.set(role, playing: false)
            onTerminate?()
            let now = Date()
            terminations = terminations.filter { now.timeIntervalSince($0) < 120 } + [now]
            let reload = terminations.count <= 3
            let url = webView.url
            let route = (url?.fragment).map { String($0.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "") } ?? "-"
            logger.error("WebContent terminated role=\(self.role.rawValue, privacy: .public) count=\(self.terminations.count, privacy: .public) route=\(route, privacy: .public) reload=\(reload, privacy: .public) url=\(url?.absoluteString ?? "-", privacy: .private)")
            guard reload else {
                // The hidden player has nothing to show: it stays unready and videos play in the main page.
                if role == .browser { showPlaceholder(in: webView) }
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
