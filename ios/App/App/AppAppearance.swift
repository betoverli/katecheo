import UIKit

/// Persists and applies the in-app Appearance preference (`light` / `dark` / `system`)
/// to every `UIWindow` before the first frame (TF219).
///
/// SceneDelegate previously forced `.unspecified`, so a saved "Light" preference only
/// took effect after visiting the Appearance screen (which called `apply` locally).
enum AppAppearance {
    static let themeDefaultsKey = "v2n.appearance.theme"
    /// Keep note editing Light even when the app theme is Dark / System (build-238).
    /// Local-only — not synced via prefs.
    static let keepEditorLightKey = "v2n.appearance.editorLight"

    /// When true, `NoteDetailViewController` forces Light while editing.
    static var keepEditorInLightMode: Bool {
        get { UserDefaults.standard.bool(forKey: keepEditorLightKey) }
        set { UserDefaults.standard.set(newValue, forKey: keepEditorLightKey) }
    }

    /// Resolved preference id: `light` | `dark` | `system`.
    static var storedTheme: String {
        get {
            if let raw = UserDefaults.standard.string(forKey: themeDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               !raw.isEmpty
            {
                return normalize(raw)
            }
            if let cached = LocalSessionCache.loadMe()?.prefs.theme {
                let id = normalize(cached)
                UserDefaults.standard.set(id, forKey: themeDefaultsKey)
                return id
            }
            return "system"
        }
        set {
            UserDefaults.standard.set(normalize(newValue), forKey: themeDefaultsKey)
        }
    }

    static func normalize(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "light", "claro": return "light"
        case "dark", "escuro": return "dark"
        default: return "system"
        }
    }

    static func style(forTheme theme: String) -> UIUserInterfaceStyle {
        switch normalize(theme) {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    /// Sync from server prefs / cache and apply to all windows.
    @MainActor
    static func sync(from prefs: NativeAPIClient.PrefsDTO, apply: Bool = true) {
        storedTheme = prefs.theme
        if apply { self.apply() }
    }

    @MainActor
    static func syncFromCacheAndApply() {
        if let me = LocalSessionCache.loadMe() {
            storedTheme = me.prefs.theme
        }
        apply()
    }

    /// Apply `storedTheme` to every window / root VC in every connected scene.
    @MainActor
    static func apply(to window: UIWindow? = nil) {
        let style = style(forTheme: storedTheme)
        func paint(_ w: UIWindow) {
            w.overrideUserInterfaceStyle = style
            w.rootViewController?.overrideUserInterfaceStyle = style
            // Presented sheets / alerts sit under root — walk the chain.
            var presented = w.rootViewController?.presentedViewController
            while let vc = presented {
                vc.overrideUserInterfaceStyle = style
                presented = vc.presentedViewController
            }
        }
        if let window {
            paint(window)
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for w in windowScene.windows {
                paint(w)
            }
        }
    }

    /// Convenience for settings UI — persist + paint immediately.
    @MainActor
    static func setTheme(_ theme: String) {
        storedTheme = theme
        if var me = LocalSessionCache.loadMe() {
            me.prefs.theme = normalize(theme)
            LocalSessionCache.saveMe(me)
        }
        apply()
    }

    @MainActor
    static func setKeepEditorInLightMode(_ enabled: Bool) {
        keepEditorInLightMode = enabled
    }
}
