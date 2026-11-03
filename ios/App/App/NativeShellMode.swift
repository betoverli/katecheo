import Foundation

/// Shell mode for the migration.
/// Phase 5: Cap site host removed — only `nativePrimary` remains.
/// Legacy `hybrid` / `capacitorSite` / `editorSpike` values in UserDefaults map to native.
enum NativeShellMode: String {
    /// Native tabs + miolo editor view only inside `NoteMioloEditorView`.
    case nativePrimary
    /// Legacy aliases kept for decoding old UserDefaults (never returned as current).
    case hybrid
    case capacitorSite
    case editorSpike

    static let defaultsKey = "verse2note.nativeShellMode"
    static let infoPlistKey = "Verse2NoteNativeShellMode"
    static let didChangeNotification = Notification.Name("verse2note.nativeShellModeDidChange")

    static var current: NativeShellMode {
        // Phase 5: always native primary regardless of stale UserDefaults / Info.plist.
        return .nativePrimary
    }

    static func setCurrent(_ mode: NativeShellMode, notify: Bool = true) {
        // Ignore attempts to re-enable Cap site — force native.
        let resolved: NativeShellMode = .nativePrimary
        UserDefaults.standard.set(resolved.rawValue, forKey: defaultsKey)
        print("[NativeShellMode] \(resolved.rawValue) (requested \(mode.rawValue))")
        if notify {
            NotificationCenter.default.post(name: didChangeNotification, object: resolved.rawValue)
        }
    }
}
