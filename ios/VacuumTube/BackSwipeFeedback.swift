import UIKit

// Swipe from the right edge: a bubble with an arrow follows the finger and the page shrinks a little,
// then "back" is performed or the page springs back.
@MainActor
final class BackSwipeFeedback: NSObject {
    private static let distance: CGFloat = 72
    private static let velocity: CGFloat = 600

    private weak var shell: ShellView?
    private let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private var reachedThreshold = false

    func attach(shell: ShellView, strip: UIView) {
        self.shell = shell
        indicator.layer.cornerRadius = 22
        indicator.alpha = 0
        indicator.isUserInteractionEnabled = false
        let arrow = UIImageView(image: UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        arrow.tintColor = .white
        arrow.frame = indicator.bounds
        arrow.contentMode = .center
        indicator.addSubview(arrow)
        shell.addSubview(indicator)
        strip.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard let shell else { return }
        let canBack = shell.state.canBack
        let translation = -gesture.translation(in: shell).x
        // Where back is not possible the bubble only shows a short, grey nudge.
        let progress = min(canBack ? 1 : 0.4, max(0, translation / Self.distance))

        switch gesture.state {
        case .began:
            haptics.prepare()
            reachedThreshold = false
            indicator.backgroundColor = canBack ? UIColor.black.withAlphaComponent(0.6) : UIColor.gray.withAlphaComponent(0.6)
            indicator.transform = .identity
        case .changed:
            apply(progress: progress, y: gesture.location(in: shell).y, canBack: canBack)
            if canBack && progress >= 1 && !reachedThreshold {
                reachedThreshold = true
                haptics.impactOccurred()
            } else if progress < 1 {
                reachedThreshold = false
            }
        case .ended:
            let velocity = -gesture.velocity(in: shell).x
            if canBack && (translation >= Self.distance || (velocity >= Self.velocity && translation > 20)) {
                complete(in: shell)
            } else {
                cancel(in: shell)
            }
        default:
            cancel(in: shell)
        }
    }

    private func apply(progress p: CGFloat, y: CGFloat, canBack: Bool) {
        guard let shell else { return }
        indicator.center = CGPoint(x: shell.bounds.maxX - 56 * p, y: min(max(y, 40), shell.bounds.maxY - 40))
        indicator.alpha = canBack ? p : p / 0.4 * 0.7
        indicator.transform = p >= 1 ? CGAffineTransform(scaleX: 1.1, y: 1.1) : .identity
        guard canBack else { return }
        let web = shell.webView
        web.layer.masksToBounds = true
        web.layer.cornerRadius = 16 * p
        web.transform = CGAffineTransform(translationX: -16 * p, y: 0).scaledBy(x: 1 - 0.05 * p, y: 1 - 0.05 * p)
    }

    private func complete(in shell: ShellView) {
        shell.webView.evaluateJavaScript("window.__vtBack?.()")
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            self.indicator.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            self.indicator.alpha = 0
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            shell.webView.transform = .identity
            shell.webView.layer.cornerRadius = 0
        } completion: { _ in
            shell.webView.layer.masksToBounds = false
        }
    }

    private func cancel(in shell: ShellView) {
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: []) {
            shell.webView.transform = .identity
            shell.webView.layer.cornerRadius = 0
            self.indicator.alpha = 0
            self.indicator.center.x = shell.bounds.maxX
        } completion: { _ in
            shell.webView.layer.masksToBounds = false
        }
    }
}
