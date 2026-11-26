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

// Hosts the web views and the native gesture feedback around them. Pages are only moved with `transform`:
// their bounds do not change, so a page is not laid out again while a finger drags it.
//
// Two Leanback pages live here. `webView` is the browsing page. Videos opened from it are played by `playerWebView`,
// a second page created shortly after the first one has loaded and kept hidden (alpha 0, media suspended) until a video is opened.
final class ShellView: UIView {
    private static let warmUpDelay: TimeInterval = 3

    let webView: WKWebView
    private(set) var playerWebView: WKWebView?
    private(set) var playerOpen = false
    private let coordinator: LeanbackView.Coordinator
    private var playerCoordinator: LeanbackView.Coordinator?
    private var playerReady = false
    private var warmUpScheduled = false
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

        coordinator.onRoute = { [weak self] message in self?.route(message) }
        // A reloaded page has lost `__vtPlayerReady`.
        coordinator.onDidCommit = { [weak self] in
            if self?.playerReady == true { self?.markPlayerReady(playerReady: true) }
        }
        coordinator.onDidFinish = { [weak self] in
            if self?.playerReady == true { self?.markPlayerReady(playerReady: true) }
            self?.scheduleWarmUp()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The page the user is looking at and touching.
    var frontWebView: WKWebView { playerOpen ? (playerWebView ?? webView) : webView }

    var state: PageState { playerOpen ? (playerCoordinator?.state ?? PageState()) : coordinator.state }

    // MARK: Player page

    private func scheduleWarmUp() {
        guard !warmUpScheduled else { return }
        warmUpScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.warmUpDelay) { [weak self] in self?.warmUp() }
    }

    private func warmUp() {
        guard playerWebView == nil else { return }
        let coordinator = LeanbackView.Coordinator(role: .player)
        let player = WebViewFactory.make(role: .player, coordinator: coordinator)
        coordinator.attach(player)
        player.frame = bounds
        player.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        player.alpha = 0
        player.isUserInteractionEnabled = false
        insertSubview(player, aboveSubview: webView)
        coordinator.onRoute = { [weak self] message in self?.route(message) }
        coordinator.onTerminate = { [weak self] in self?.playerTerminated() }
        playerCoordinator = coordinator
        playerWebView = player
        Task { await player.setAllMediaPlaybackSuspended(true) }
        #if DEBUG
        NSLog("[vt:player] warm-up")
        #endif
        player.load(URLRequest(url: Shell.startURL))
    }

    private func markPlayerReady(playerReady ready: Bool) {
        webView.evaluateJavaScript("window.__vtPlayerReady = \(ready)")
    }

    private func route(_ message: [String: Any]) {
        let command = message["command"] as? String
        switch message["type"] as? String {
        case "ready":
            guard playerWebView != nil else { return }
            playerReady = true
            markPlayerReady(playerReady: true)
            #if DEBUG
            NSLog("[vt:player] ready")
            #endif
        case "open":
            if let command { openPlayer(command: command) }
        case "close":
            closePlayer()
        case "forward":
            if let command { forward(command: command) }
        case "log":
            #if DEBUG
            NSLog("[vt:route] %@", String(describing: message["text"] ?? ""))
            #endif
        default:
            break
        }
    }

    private func openPlayer(command: String) {
        guard playerReady, let player = playerWebView else { return }
        let alreadyOpen = playerOpen
        playerOpen = true
        webView.isUserInteractionEnabled = false
        player.isUserInteractionEnabled = true
        Task {
            await player.setAllMediaPlaybackSuspended(false)
            player.callAsyncJavaScript("return await window.__vtOpen?.(command)", arguments: ["command": command], in: nil, in: .page) { _ in }
            await webView.setAllMediaPlaybackSuspended(true)
        }
        if alreadyOpen { return }
        player.layer.removeAllAnimations()
        player.transform = CGAffineTransform(translationX: 0, y: bounds.height)
        player.alpha = 1
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            player.transform = .identity
        }
        #if DEBUG
        NSLog("[vt:player] open")
        #endif
    }

    /// Slides the player away and hides it.
    private func closePlayer() {
        guard playerOpen, let player = playerWebView else { return }
        playerOpen = false
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn]) {
            player.transform = CGAffineTransform(translationX: 0, y: self.bounds.height)
        } completion: { _ in
            self.hidePlayer(player)
        }
        returnToBrowser()
    }

    /// The player is already out of sight (swipe down).
    func closePlayerOffscreen() {
        guard playerOpen, let player = playerWebView else { return }
        playerOpen = false
        hidePlayer(player)
        returnToBrowser()
    }

    private func hidePlayer(_ player: WKWebView) {
        guard !playerOpen else { return }
        player.alpha = 0
        player.transform = .identity
        player.layer.cornerRadius = 0
        player.layer.masksToBounds = false
        player.isUserInteractionEnabled = false
        // The player page goes back to its home screen, which stops the video; then it sleeps.
        player.callAsyncJavaScript("return await window.__vtLeavePlayer?.()", arguments: [:], in: nil, in: .page) { _ in
            MainActor.assumeIsolated {
                guard !self.playerOpen else { return }
                Task { await player.setAllMediaPlaybackSuspended(true) }
            }
        }
    }

    private func returnToBrowser() {
        webView.isUserInteractionEnabled = true
        Task { await webView.setAllMediaPlaybackSuspended(false) }
    }

    private func forward(command: String) {
        closePlayer()
        webView.callAsyncJavaScript("return await window.__vtExecute?.(command)", arguments: ["command": command], in: nil, in: .page) { _ in }
    }

    private func playerTerminated() {
        playerReady = false
        markPlayerReady(playerReady: false)
        guard playerOpen, let player = playerWebView else { return }
        playerOpen = false
        player.layer.removeAllAnimations()
        player.alpha = 0
        player.transform = .identity
        player.isUserInteractionEnabled = false
        returnToBrowser()
    }
}
