import UIKit

enum PlayerMode {
    case hidden
    case full
    case mini
}

// Holds the player page. In full mode it covers the shell; in mini mode it is a small rounded window in the corner showing
// the page's video. The page itself is never resized (it keeps the size of the shell): it is scaled and moved with `transform`
// so that its video lands in the window and everything else is clipped.
final class PlayerContainerView: UIView {
    private let overlay = UIView()
    private let closeButton = UIButton(type: .custom)
    var onExpand: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .black

        overlay.backgroundColor = .clear
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(expandTapped)))
        addSubview(overlay)

        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.6)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        closeButton.configuration = config
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        closeButton.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        overlay.addSubview(closeButton)
        setControlsVisible(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlay.frame = bounds
        closeButton.frame = CGRect(x: bounds.width - 38, y: 8, width: 30, height: 30)
    }

    // The close button is 30 pt, its touch area 44 pt.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !overlay.isHidden else { return super.hitTest(point, with: event) }
        if closeButton.frame.insetBy(dx: -7, dy: -7).contains(point) { return closeButton }
        return super.hitTest(point, with: event)
    }

    func setControlsVisible(_ visible: Bool) {
        overlay.isHidden = !visible
        overlay.isUserInteractionEnabled = visible
    }

    @objc private func expandTapped() { onExpand?() }
}

// Where the page and its container go for a given progress between full (0) and mini (1).
struct MiniGeometry {
    let bounds: CGRect
    let safeArea: UIEdgeInsets
    /// The displayed video inside the page; nil until the page said where it is.
    let video: CGRect?

    var miniFrame: CGRect {
        let width = min(420, max(300, bounds.width * 0.28))
        let height = (width * 9 / 16).rounded()
        return CGRect(
            x: bounds.maxX - 20 - max(0, safeArea.right) - width,
            y: bounds.maxY - 20 - max(0, safeArea.bottom) - height,
            width: width,
            height: height
        )
    }

    private var videoRect: CGRect {
        video ?? CGRect(x: 0, y: (bounds.height - bounds.width * 9 / 16) / 2, width: bounds.width, height: bounds.width * 9 / 16)
    }

    func frame(_ p: CGFloat) -> CGRect {
        let a = bounds, b = miniFrame
        return CGRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
                      width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
    }

    func transform(_ p: CGFloat) -> CGAffineTransform {
        let mini = miniFrame
        let v = videoRect
        let scaleMini = min(mini.width / v.width, mini.height / v.height)
        let tx = mini.width / 2 - bounds.width / 2 - scaleMini * (v.midX - bounds.width / 2)
        let ty = mini.height / 2 - bounds.height / 2 - scaleMini * (v.midY - bounds.height / 2)
        let scale = 1 + (scaleMini - 1) * p
        return CGAffineTransform(translationX: tx * p, y: ty * p).scaledBy(x: scale, y: scale)
    }
}
