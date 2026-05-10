import Foundation

enum NotionTokenStore {
    private static let tokenKey = "notionAccessToken"
    private static let workspaceIdKey = "notionWorkspaceId"
    private static let workspaceNameKey = "notionWorkspaceName"

    static var accessToken: String? {
        get { KeychainStore.load(key: tokenKey) }
    }

    static var workspaceId: String? {
        get { UserDefaults.standard.string(forKey: workspaceIdKey) }
    }

    static var workspaceName: String? {
        get { UserDefaults.standard.string(forKey: workspaceNameKey) }
    }

    static var isAuthorized: Bool {
        accessToken != nil
    }

    static func save(accessToken: String, workspaceId: String?, workspaceName: String?) throws {
        try KeychainStore.save(key: tokenKey, value: accessToken)
        if let id = workspaceId {
            UserDefaults.standard.set(id, forKey: workspaceIdKey)
        }
        if let name = workspaceName {
            UserDefaults.standard.set(name, forKey: workspaceNameKey)
        }
    }

    static func clear() {
        KeychainStore.delete(key: tokenKey)
        UserDefaults.standard.removeObject(forKey: workspaceIdKey)
        UserDefaults.standard.removeObject(forKey: workspaceNameKey)
    }
}
