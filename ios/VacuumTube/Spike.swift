import Foundation

// Phase 0 spike knobs, overridable via launch arguments, e.g. `-touch 1 -url https://... -ua "..."`.
enum Spike {
    // Cobalt UA in the exact format of src/ua.js, with os/model for iPad.
    static let cobaltUserAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
        let year = Calendar.current.component(.year, from: Date())
        return "Mozilla/5.0 (iPad; CPU OS 27_0 like Mac OS X) Cobalt/27.lts.3.1040976-gold (unlike Gecko) v8/13.8.258.54-jit gles Starboard/18, VacuumTube_DESKTOP_arm64_\(year)/\(version) (VacuumTube, iPadOS) rocks.shy.VacuumTube/\(version)"
    }()

    static var userAgent: String { UserDefaults.standard.string(forKey: "ua") ?? cobaltUserAgent }
    static var startURL: URL { URL(string: UserDefaults.standard.string(forKey: "url") ?? "https://www.youtube.com/tv")! }
    static var touchSupport: Bool { UserDefaults.standard.bool(forKey: "touch") }

    // Documents/inject.js, if present, runs at document start (for trying upstream modules without rebuilding).
    static var injectedScript: String? {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return try? String(contentsOf: dir.appendingPathComponent("inject.js"), encoding: .utf8)
    }
}
