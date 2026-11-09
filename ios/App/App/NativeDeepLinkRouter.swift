import UIKit

/// Routes universal links, custom scheme URLs, and push `href` payloads to native screens.
/// Never opens the Capacitor site host.
enum NativeDeepLinkRouter {
    enum Destination: Equatable {
        case notebook
        case note(id: String)
        case groups
        case group(id: String)
        case verses
        case themes
        case reading
        case readingPlan(id: String)
        case readingInvite(groupId: String)
        case profile
        case signIn
        case unknown
    }

    static func destination(for url: URL) -> Destination {
        let host = (url.host ?? "").lowercased()
        let scheme = url.scheme?.lowercased() ?? ""
        let isAppHost = host.isEmpty
            || AppSite.acceptedHosts.contains(host)
            || scheme == "verse2note"
            || scheme == "katecheo"
        guard isAppHost else { return .unknown }

        var path = url.path
        if path.hasPrefix("/") { path = String(path.dropFirst()) }
        let parts = path.split(separator: "/").map(String.init)

        if parts.isEmpty { return .notebook }

        switch parts[0] {
        case "notebook":
            if parts.count >= 2, !parts[1].isEmpty, parts[1] != "import" {
                return .note(id: parts[1])
            }
            return .notebook
        case "n":
            if parts.count >= 2, !parts[1].isEmpty { return .note(id: parts[1]) }
            return .notebook
        case "groups":
            if parts.count >= 2, !parts[1].isEmpty { return .group(id: parts[1]) }
            return .groups
        case "g":
            if parts.count >= 2, !parts[1].isEmpty { return .readingInvite(groupId: parts[1]) }
            return .reading
        case "app", "collections", "c":
            if parts[0] == "collections" { return .themes }
            return .verses
        case "reading":
            if parts.count >= 2, !parts[1].isEmpty, parts[1] != "all", parts[1] != "category" {
                return .readingPlan(id: parts[1])
            }
            return .reading
        case "profile", "u", "inbox":
            return .profile
        case "login", "auth":
            return .signIn
        case "native-editor", "native-phase0":
            // Editor is embedded; cold open → Caderno.
            return .notebook
        default:
            return .notebook
        }
    }

    /// Parse push payload `href` (absolute or path-only).
    static func destination(href: String) -> Destination {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        if trimmed.hasPrefix("/"), !trimmed.hasPrefix("//") {
            if let url = URL(string: "\(AppSite.baseURL.absoluteString)\(trimmed)") {
                return destination(for: url)
            }
        }
        if let url = URL(string: trimmed) {
            return destination(for: url)
        }
        return .unknown
    }

    /// Tab indices: 0 Caderno · 1 Grupos · 2 Ferramentas · 3 Perfil
    private enum Tab: Int {
        case notebook = 0
        case groups = 1
        case tools = 2
        case profile = 3
    }

    @MainActor
    static func open(_ destination: Destination, animated: Bool = true) {
        guard destination != .unknown else { return }
        guard let tabs = rootTabBar() else {
            // Root not ready yet (cold start) — retry shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                open(destination, animated: animated)
            }
            return
        }

        switch destination {
        case .verses, .themes, .reading:
            tabs.selectedIndex = Tab.tools.rawValue
            if let nav = tabs.selectedViewController as? UINavigationController {
                nav.popToRootViewController(animated: false)
                if let home = nav.viewControllers.first as? VersesHomeViewController {
                    _ = home.view
                    switch destination {
                    case .themes:
                        home.selectHomeFilter("themes")
                    case .reading:
                        home.selectHomeFilter("reading")
                    default:
                        home.selectHomeFilter("books")
                    }
                }
            }
        case .groups, .group:
            tabs.selectedIndex = Tab.groups.rawValue
            if case .group(let id) = destination,
               let nav = tabs.selectedViewController as? UINavigationController
            {
                nav.popToRootViewController(animated: false)
                Task { @MainActor in
                    do {
                        let group = try await NativeAPIClient.getGroup(id: id)
                        let list = NotebookListViewController(group: group)
                        nav.pushViewController(list, animated: animated)
                    } catch {
                        // Stay on Grupos home if fetch fails (offline).
                    }
                }
            }
        case .notebook, .note:
            tabs.selectedIndex = Tab.notebook.rawValue
            if case .note(let id) = destination,
               let nav = tabs.selectedViewController as? UINavigationController
            {
                nav.popToRootViewController(animated: false)
                let cached = LocalNoteCache.loadNotes().first { $0.id == id }
                nav.pushViewController(NoteDetailViewController(noteId: id, initial: cached), animated: animated)
            }
        case .readingPlan(let id):
            tabs.selectedIndex = Tab.tools.rawValue
            if let nav = tabs.selectedViewController as? UINavigationController {
                nav.popToRootViewController(animated: false)
                if let home = nav.viewControllers.first as? VersesHomeViewController {
                    _ = home.view
                    home.selectHomeFilter("reading")
                }
                nav.pushViewController(ReadingPlanDetailViewController(planId: id), animated: animated)
            }
        case .readingInvite(let groupId):
            tabs.selectedIndex = Tab.tools.rawValue
            if let nav = tabs.selectedViewController as? UINavigationController {
                nav.popToRootViewController(animated: false)
                if let home = nav.viewControllers.first as? VersesHomeViewController {
                    _ = home.view
                    home.selectHomeFilter("reading")
                }
                Task { @MainActor in
                    do {
                        if NativeAPIClient.hasBearer {
                            let planId = try await NativeAPIClient.joinReadingPlanGroup(groupId: groupId)
                            nav.pushViewController(ReadingPlanDetailViewController(planId: planId), animated: animated)
                        } else {
                            NotificationCenter.default.post(name: .nativeOpenSignIn, object: nil)
                        }
                    } catch {
                        // Stay on Leitura (Ferramentas → Leitura) if join fails.
                    }
                }
            }
        case .profile, .signIn:
            tabs.selectedIndex = Tab.profile.rawValue
            if destination == .signIn, !NativeAPIClient.hasBearer {
                NotificationCenter.default.post(name: .nativeOpenSignIn, object: nil)
            }
        case .unknown:
            break
        }
    }

    @MainActor
    static func open(url: URL, animated: Bool = true) {
        open(destination(for: url), animated: animated)
    }

    @MainActor
    static func open(href: String, animated: Bool = true) {
        open(destination(href: href), animated: animated)
    }

    @MainActor
    private static func rootTabBar() -> NativeRootTabBarController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        if let tabs = window?.rootViewController as? NativeRootTabBarController {
            return tabs
        }
        return nil
    }
}

extension Notification.Name {
    static let nativeOpenSignIn = Notification.Name("verse2note.nativeOpenSignIn")
}
