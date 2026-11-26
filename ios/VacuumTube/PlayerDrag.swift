import UIKit
import WebKit

// Swipe down in the player. In the dedicated player page it minimizes the player: the page follows the finger towards the corner
// and settles there or springs back. In the browsing page (player not ready) it shrinks and slides away and `commit` leaves the player.
@MainActor
final class PlayerDrag: NSObject, UIGestureRecognizerDelegate {
    private static let distance: CGFloat = 140
    private static let velocity: CGFloat = 900

    /// Called once the page is out of sight; `finish(true)` brings it back with a fade, `finish(false)` leaves it to the caller.
    var commit: (_ shell: ShellView, _ finish: @escaping @MainActor (Bool) -> Void) -> Void = { shell, finish in
        shell.webView.callAsyncJavaScript("return await window.__vtLeavePlayer?.()", arguments: [:], in: nil, in: .page) { _ in
            MainActor.assumeIsolated { finish(true) }
        }
    }

    private weak var shell: ShellView?
    private var running = false

    func attach(shell: ShellView) {
        self.shell = shell
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        shell.addGestureRecognizer(pan)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let shell, !running else { return false }
        let state = shell.state
        let v = pan.velocity(in: shell)
        return state.watch && state.touchOwned && !state.sidePanel && v.y > 0 && v.y > 2 * abs(v.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard let shell else { return }
        let dy = max(0, gesture.translation(in: shell).y)
        if shell.playerFull {
            // The player page is minimized: it follows the finger towards the corner.
            switch gesture.state {
            case .began:
                shell.beginPlayerDrag()
            case .changed:
                shell.dragPlayer(progress: min(1, dy / (0.5 * shell.bounds.height)))
            case .ended:
                shell.settlePlayer(toMini: dy >= Self.distance || gesture.velocity(in: shell).y >= Self.velocity)
            case .cancelled, .failed:
                shell.settlePlayer(toMini: false)
            default:
                break
            }
            return
        }
        switch gesture.state {
        case .changed:
            follow(dy: dy, in: shell)
        case .ended:
            if dy >= Self.distance || gesture.velocity(in: shell).y >= Self.velocity { finish(in: shell) } else { cancel(in: shell) }
        case .cancelled, .failed:
            cancel(in: shell)
        default:
            break
        }
    }

    private func follow(dy: CGFloat, in shell: ShellView) {
        let p = min(1, dy / (0.5 * shell.bounds.height))
        let web = shell.frontWebView
        web.layer.masksToBounds = true
        web.layer.cornerRadius = 20 * p
        web.transform = CGAffineTransform(translationX: 0, y: dy).scaledBy(x: 1 - 0.2 * p, y: 1 - 0.2 * p)
    }

    private func reset(_ web: WKWebView) {
        web.transform = .identity
        web.layer.cornerRadius = 0
        web.layer.masksToBounds = false
    }

    private func finish(in shell: ShellView) {
        running = true
        let web = shell.frontWebView
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
            web.transform = CGAffineTransform(translationX: 0, y: shell.bounds.height).scaledBy(x: 0.8, y: 0.8)
            web.alpha = 0
        } completion: { _ in
            self.commit(shell) { reveal in
                guard reveal else {
                    self.running = false
                    return
                }
                self.reset(web)
                UIView.animate(withDuration: 0.2) { web.alpha = 1 } completion: { _ in self.running = false }
            }
        }
    }

    private func cancel(in shell: ShellView) {
        let web = shell.frontWebView
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: []) {
            web.transform = .identity
            web.layer.cornerRadius = 0
        } completion: { _ in
            web.layer.masksToBounds = false
        }
    }
}
