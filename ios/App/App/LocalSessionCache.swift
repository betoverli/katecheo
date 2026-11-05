import Foundation

/// On-device mirror of profile + groups so offline / cold paint never looks logged out.
enum LocalSessionCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("NativeSession", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var meURL: URL { directory.appendingPathComponent("me-v1.json") }
    private static var groupsURL: URL { directory.appendingPathComponent("groups-v1.json") }
    private static let offlineFlagKey = "v2n.session.offlineBanner"

    static func saveMe(_ me: NativeAPIClient.MeDTO) {
        guard let data = try? JSONEncoder().encode(me) else { return }
        try? data.write(to: meURL, options: .atomic)
    }

    static func loadMe() -> NativeAPIClient.MeDTO? {
        guard let data = try? Data(contentsOf: meURL),
              let me = try? JSONDecoder().decode(NativeAPIClient.MeDTO.self, from: data)
        else { return nil }
        return me
    }

    static func clearMe() {
        try? FileManager.default.removeItem(at: meURL)
    }

    static func saveGroups(_ groups: [NativeAPIClient.GroupDTO]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        try? data.write(to: groupsURL, options: .atomic)
    }

    static func loadGroups() -> [NativeAPIClient.GroupDTO] {
        guard let data = try? Data(contentsOf: groupsURL),
              let groups = try? JSONDecoder().decode([NativeAPIClient.GroupDTO].self, from: data)
        else { return [] }
        return groups
    }

    static func clearGroups() {
        try? FileManager.default.removeItem(at: groupsURL)
    }

    static func clearAll() {
        clearMe()
        clearGroups()
    }

    static var showOfflineHint: Bool {
        get { UserDefaults.standard.bool(forKey: offlineFlagKey) }
        set { UserDefaults.standard.set(newValue, forKey: offlineFlagKey) }
    }
}
