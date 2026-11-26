import UIKit

// The screen stays awake while any of the web views plays.
@MainActor
enum PlaybackTracker {
    private static var playing: [WebViewRole: Bool] = [:]

    static func set(_ role: WebViewRole, playing value: Bool) {
        playing[role] = value
        UIApplication.shared.isIdleTimerDisabled = playing.values.contains(true)
    }
}
