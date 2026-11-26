import UIKit
import WebKit

// What touch.js reports through `vtState`.
struct PageState {
    var watch = false
    var shorts = false
    var sidePanel = false
    var canBack = false
    var touchOwned = false

    init() {}

    init(_ body: [String: Any]) {
        watch = body["watch"] as? Bool ?? false
        shorts = body["shorts"] as? Bool ?? false
        sidePanel = body["sidePanel"] as? Bool ?? false
        canBack = body["canBack"] as? Bool ?? false
        touchOwned = body["touchOwned"] as? Bool ?? false
    }
}

// Hosts the web view and the native gesture feedback around it. The web view is only moved with `transform`:
// its bounds do not change, so the page is not laid out again while a finger drags it.
final class ShellView: UIView {
    let webView: WKWebView
    private let coordinator: LeanbackView.Coordinator
    private let strip = UIView()
    private let backFeedback: BackSwipeFeedback
    private let playerDrag: PlayerDrag

    init(webView: WKWebView, coordinator: LeanbackView.Coordinator) {
        self.webView = webView
        self.coordinator = coordinator
        self.backFeedback = BackSwipeFeedback()
        self.playerDrag = PlayerDrag()
        super.init(frame: .zero)
        backgroundColor = Shell.backgroundColor

        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)

        // Touches starting on this strip never reach the page, so the back swipe cannot scroll a shelf or tap the rail.
        // Right edge only: Stage Manager owns the left edge and does not defer it.
        strip.frame = CGRect(x: bounds.width - 20, y: 0, width: 20, height: bounds.height)
        strip.autoresizingMask = [.flexibleHeight, .flexibleLeftMargin]
        addSubview(strip)

        backFeedback.attach(shell: self, strip: strip)
        playerDrag.attach(shell: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    var state: PageState { coordinator.state }
}
