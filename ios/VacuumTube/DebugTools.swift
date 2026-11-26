#if DEBUG
import WebKit

extension LeanbackView.Coordinator {
    func startDebugTools(for webView: WKWebView) {
        let role = self.role
        urlObservation = webView.observe(\.url, options: [.new]) { _, change in
            let url = change.newValue??.absoluteString ?? "nil"
            Task { @MainActor in NSLog("[vt:%@] url %@", role.rawValue, url) }
        }
        // Remote eval: drop JS into Documents/cmd.js (browser) or cmd-player.js (player), result goes to the log.
        commandTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runPendingCommand() }
        }
    }

    private func runPendingCommand() {
        guard let webView,
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let file = dir.appendingPathComponent(self.role == .player ? "cmd-player.js" : "cmd.js")
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: file)
        let role = self.role
        webView.callAsyncJavaScript(source, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value):
                NSLog("[vt:%@] eval ok %@", role.rawValue, String(describing: value))
            case .failure(let error):
                NSLog("[vt:%@] eval error %@", role.rawValue, String(describing: error))
            }
        }
    }
}
#endif
