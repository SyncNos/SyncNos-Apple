import Foundation

struct NotionSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var syncEnabled: Bool {
        get { defaults.bool(forKey: Keys.syncEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Keys.syncEnabled) }
    }

    var parentPageId: String {
        get { defaults.string(forKey: Keys.parentPageId) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Keys.parentPageId) }
    }

    var parentPageTitle: String {
        get { defaults.string(forKey: Keys.parentPageTitle) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Keys.parentPageTitle) }
    }

    var healthDatabaseIdOverride: String {
        get { defaults.string(forKey: Keys.healthDatabaseIdOverride) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Keys.healthDatabaseIdOverride) }
    }

    func clear() {
        defaults.removeObject(forKey: Keys.syncEnabled)
        defaults.removeObject(forKey: Keys.parentPageId)
        defaults.removeObject(forKey: Keys.parentPageTitle)
        defaults.removeObject(forKey: Keys.healthDatabaseIdOverride)
    }

    private enum Keys {
        static let syncEnabled = "syncEnabled"
        static let parentPageId = "parentPageId"
        static let parentPageTitle = "parentPageTitle"
        static let healthDatabaseIdOverride = "healthDatabaseIdOverride"
    }
}
