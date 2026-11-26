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
// The player page sits in a container and is either full-screen or a mini player in the corner while browsing goes on.
final class ShellView: UIView {
    private static let warmUpDelay: TimeInterval = 3

    let webView: WKWebView
    private(set) var playerWebView: WKWebView?
    private(set) var playerMode = PlayerMode.hidden
    private let coordinator: LeanbackView.Coordinator
    private var playerCoordinator: LeanbackView.Coordinator?
    private var playerReady = false
    private var warmUpScheduled = false
    private let strip = UIView()
    private let backFeedback: BackSwipeFeedback
    private let playerDrag: PlayerDrag
    private let miniShadow = UIView()
    private let container = PlayerContainerView()
    private var videoRect: CGRect?
    private var videoRectRequest = 0
    private var progress: CGFloat = 0
    private var miniShorts = false
    private var laidOutSize = CGSize.zero

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

        miniShadow.backgroundColor = .black
        miniShadow.layer.shadowColor = UIColor.black.cgColor
        miniShadow.layer.shadowOpacity = 0.45
        miniShadow.layer.shadowRadius = 14
        miniShadow.layer.shadowOffset = CGSize(width: 0, height: 6)
        miniShadow.alpha = 0
        miniShadow.isUserInteractionEnabled = false
        addSubview(miniShadow)

        container.alpha = 0
        container.isUserInteractionEnabled = false
        container.onExpand = { [weak self] in self?.expandPlayer() }
        container.onClose = { [weak self] in self?.closePlayer() }
        addSubview(container)

        // Touches starting on this strip never reach the page, so the back swipe cannot scroll a shelf or tap the rail.
        // Right edge only: Stage Manager owns the left edge and does not defer it.
        strip.frame = CGRect(x: bounds.width - 20, y: 0, width: 20, height: bounds.height)
        strip.autoresizingMask = [.flexibleHeight, .flexibleLeftMargin]
        addSubview(strip)

        backFeedback.attach(shell: self, strip: strip)
        playerDrag.attach(shell: self)

        coordinator.onRoute = { [weak self] message in self?.route(message) }
        // A reloaded page has lost `__vtPlayerReady`.
        coordinator.onDidCommit = { [weak self] in self?.browserLoaded() }
        coordinator.onDidFinish = { [weak self] in
            self?.browserLoaded()
            self?.scheduleWarmUp()
        }
        coordinator.onStateChange = { [weak self] in self?.browserStateChanged() }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The page the user is touching: the player only while it is full-screen.
    var frontWebView: WKWebView { playerMode == .full ? (playerWebView ?? webView) : webView }

    var playerFull: Bool { playerMode == .full }

    var state: PageState { playerMode == .full ? (playerCoordinator?.state ?? PageState()) : coordinator.state }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        guard let player = playerWebView else { return }
        player.transform = .identity
        player.frame = CGRect(origin: .zero, size: bounds.size)
        apply(progress: playerMode == .mini ? 1 : 0)
        // The page lays itself out again for the new size, not instantly: until it says where its video is now, the old rectangle stays
        // (no jump), and it is asked a few times because the first answer may still be the old layout.
        if playerMode == .mini {
            for delay in [0.3, 0.8, 1.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshVideoRect() }
            }
        }
    }

    // MARK: Player page

    private func browserLoaded() {
        if playerReady { markPlayerReady(playerReady: true) }
        if playerMode != .hidden { setBrowserQuiet(!(playerMode == .mini && miniShorts)) }
    }

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
        player.frame = CGRect(origin: .zero, size: bounds.size)
        player.isUserInteractionEnabled = false
        container.frame = bounds
        container.insertSubview(player, at: 0)
        coordinator.onRoute = { [weak self] message in self?.route(message) }
        coordinator.onTerminate = { [weak self] in self?.playerTerminated() }
        playerCoordinator = coordinator
        playerWebView = player
        Task { await suspend(player, true) }
        #if DEBUG
        NSLog("[vt:player] warm-up")
        #endif
        player.load(URLRequest(url: Shell.startURL))
    }

    private func suspend(_ web: WKWebView, _ value: Bool) async {
        await web.setAllMediaPlaybackSuspended(value)
    }

    // The browsing page is kept quiet from JS rather than suspended: WebKit does not let a page that was suspended play again
    // (play() is refused afterwards), and Shorts must keep playing while the mini player waits.
    private func setBrowserQuiet(_ quiet: Bool) {
        webView.evaluateJavaScript("window.__vtQuiet?.(\(quiet))")
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
        case "pipInline":
            // Back from the system PiP window: the player belongs on the screen again.
            if playerMode == .mini { expandPlayer() }
        case "log":
            #if DEBUG
            NSLog("[vt:route] %@", String(describing: message["text"] ?? ""))
            #endif
        default:
            break
        }
    }

    // MARK: Geometry

    private var geometry: MiniGeometry { MiniGeometry(bounds: bounds, safeArea: window?.safeAreaInsets ?? .zero, video: videoRect) }

    /// Puts the container and the page at `p`: 0 is full-screen, 1 is the mini player.
    private func apply(progress p: CGFloat) {
        guard let player = playerWebView else { return }
        progress = p
        let g = geometry
        container.frame = g.frame(p)
        miniShadow.frame = container.frame
        player.transform = g.transform(p)
        container.layer.cornerRadius = 12 * p
        miniShadow.layer.cornerRadius = 12 * p
        miniShadow.alpha = p
    }

    private func animate(to p: CGFloat, spring: Bool = true, completion: (@MainActor () -> Void)? = nil) {
        let changes = { self.apply(progress: p) }
        if spring {
            UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: changes) { _ in
                MainActor.assumeIsolated { completion?() }
            }
        } else {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: changes) { _ in
                MainActor.assumeIsolated { completion?() }
            }
        }
    }

    /// Asks the page where its video is, so that the drag can aim at it.
    func beginPlayerDrag() {
        refreshVideoRect()
    }

    /// The answer is asynchronous: the frame that is on the screen is kept until it arrives, and an answer to an older request is dropped.
    private func refreshVideoRect() {
        videoRectRequest += 1
        let request = videoRectRequest
        playerWebView?.evaluateJavaScript("window.__vtVideoRect?.()") { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self, request == self.videoRectRequest, let r = result as? [Double], r.count == 4, r[2] > 0, r[3] > 0 else { return }
                let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
                self.videoRect = rect
                // A drag applies it with its next move; in the mini player, with nothing animating, it is applied now.
                if self.playerMode == .mini, self.container.layer.animationKeys() == nil { self.apply(progress: 1) }
            }
        }
    }

    func dragPlayer(progress p: CGFloat) {
        guard playerMode == .full else { return }
        apply(progress: p)
    }

    func settlePlayer(toMini mini: Bool) {
        guard playerMode == .full else { return }
        if mini { minimizePlayer() } else { animate(to: 0) }
    }

    // MARK: Modes

    private func minimizePlayer() {
        guard playerMode == .full, let player = playerWebView else { return }
        playerMode = .mini
        miniShorts = coordinator.state.shorts
        player.isUserInteractionEnabled = false
        container.isUserInteractionEnabled = true
        container.setControlsVisible(true)
        webView.isUserInteractionEnabled = true
        setBrowserQuiet(!miniShorts)
        player.evaluateJavaScript("window.__vtMinimized?.(true)")
        animate(to: 1)
        #if DEBUG
        NSLog("[vt:player] mini")
        #endif
    }

    private func expandPlayer() {
        guard playerMode == .mini, let player = playerWebView else { return }
        playerMode = .full
        container.setControlsVisible(false)
        player.isUserInteractionEnabled = true
        webView.isUserInteractionEnabled = false
        Task {
            await suspend(player, false)
        }
        setBrowserQuiet(true)
        player.evaluateJavaScript("window.__vtMinimized?.(false)")
        animate(to: 0)
        #if DEBUG
        NSLog("[vt:player] full")
        #endif
    }

    private func openPlayer(command: String) {
        guard playerReady, let player = playerWebView else { return }
        switch playerMode {
        case .hidden:
            // A close that has not finished its animation may still have its UI on the screen (mini shell, corners, `__vtMini`).
            resetPlayerUI(player)
            playerMode = .full
            videoRect = nil
            videoRectRequest += 1
            container.frame = bounds
            container.transform = CGAffineTransform(translationX: 0, y: bounds.height)
            container.alpha = 1
            container.isUserInteractionEnabled = true
            player.isUserInteractionEnabled = true
            webView.isUserInteractionEnabled = false
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                self.container.transform = .identity
            }
            setBrowserQuiet(true)
            #if DEBUG
            NSLog("[vt:player] open")
            #endif
        case .mini:
            expandPlayer()
            #if DEBUG
            NSLog("[vt:player] open (from mini)")
            #endif
        case .full:
            break
        }
        Task {
            await suspend(player, false)
            player.callAsyncJavaScript("return await window.__vtOpen?.(command)", arguments: ["command": command], in: nil, in: .page) { _ in }
        }
    }

    /// Slides (full) or fades (mini) the player away and hides it.
    private func closePlayer() {
        guard playerMode != .hidden, let player = playerWebView else { return }
        let wasFull = playerMode == .full
        playerMode = .hidden
        container.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn]) {
            if wasFull {
                self.container.transform = CGAffineTransform(translationX: 0, y: self.bounds.height)
            } else {
                self.container.alpha = 0
                self.miniShadow.alpha = 0
            }
        } completion: { _ in
            MainActor.assumeIsolated { self.hidePlayer(player) }
        }
        returnToBrowser()
    }

    private func hidePlayer(_ player: WKWebView) {
        guard playerMode == .hidden else { return }
        resetPlayerUI(player)
        // The player page goes back to its home screen, which stops the video; then it sleeps.
        player.callAsyncJavaScript("return await window.__vtLeavePlayer?.()", arguments: [:], in: nil, in: .page) { _ in
            MainActor.assumeIsolated {
                guard self.playerMode == .hidden else { return }
                Task { await self.suspend(player, true) }
            }
        }
        #if DEBUG
        NSLog("[vt:player] hidden")
        #endif
    }

    /// Takes the player's native shell back to its resting state; shared by hiding and by opening (a new video may open before the close animation ends).
    private func resetPlayerUI(_ player: WKWebView) {
        container.layer.removeAllAnimations()
        miniShadow.layer.removeAllAnimations()
        container.alpha = 0
        container.transform = .identity
        container.frame = bounds
        container.layer.cornerRadius = 0
        container.setControlsVisible(false)
        container.isUserInteractionEnabled = false
        miniShadow.alpha = 0
        player.transform = .identity
        player.layer.cornerRadius = 0
        player.layer.masksToBounds = false
        player.isUserInteractionEnabled = false
        player.evaluateJavaScript("window.__vtMini = false")
    }

    private func returnToBrowser() {
        webView.isUserInteractionEnabled = true
        setBrowserQuiet(false)
    }

    private func forward(command: String) {
        closePlayer()
        webView.callAsyncJavaScript("return await window.__vtExecute?.(command)", arguments: ["command": command], in: nil, in: .page) { _ in }
    }

    /// While the mini player waits, browsing is silent, except in Shorts: they play with sound and the mini player stays paused.
    private func browserStateChanged() {
        guard playerMode == .mini else { return }
        let shorts = coordinator.state.shorts
        guard shorts != miniShorts else { return }
        miniShorts = shorts
        #if DEBUG
        NSLog("[vt:browser] mini + shorts=%@ -> browser quiet=%@", String(shorts), String(!shorts))
        #endif
        if shorts { playerWebView?.evaluateJavaScript("window.__vtPause?.()") }
        setBrowserQuiet(!shorts)
    }

    private func playerTerminated() {
        playerReady = false
        markPlayerReady(playerReady: false)
        guard playerMode != .hidden, let player = playerWebView else { return }
        playerMode = .hidden
        hidePlayer(player)
        returnToBrowser()
    }
}
