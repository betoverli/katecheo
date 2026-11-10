import Foundation

/// Shell mode for the migration.
/// Phase 5+: Cap site host removed — only `nativePrimary` remains.
/// Phase 7: note body is `NativeNoteEditorView` (no WebView).
/// Legacy `hybrid` / `capacitorSite` / `editorSpike` values in UserDefaults map to native.
enum NativeShellMode: String {
    /// Native tabs + native note editor (`NativeNoteEditorView`).
    case nativePrimary
    /// Legacy aliases kept for decoding old UserDefaults (never returned as current).
    case hybrid
    case capacitorSite
    case editorSpike

    static let defaultsKey = "katecheo.nativeShellMode"
    static let infoPlistKey = "KatecheoNativeShellMode"
    static let didChangeNotification = Notification.Name("katecheo.nativeShellModeDidChange")

    static var current: NativeShellMode {
        // Phase 5: always native primary regardless of stale UserDefaults / Info.plist.
        return .nativePrimary
    }

    static func setCurrent(_ mode: NativeShellMode, notify: Bool = true) {
        // Ignore attempts to re-enable Cap site — force native.
        let resolved: NativeShellMode = .nativePrimary
        UserDefaults.standard.set(resolved.rawValue, forKey: defaultsKey)
        #if DEBUG
        print("[NativeShellMode] \(resolved.rawValue) (requested \(mode.rawValue))")
        #endif
        if notify {
            NotificationCenter.default.post(name: didChangeNotification, object: resolved.rawValue)
        }
    }
}
