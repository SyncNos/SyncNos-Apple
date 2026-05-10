import Combine
import Foundation

@MainActor
final class NotionSettingsViewModel: ObservableObject {
    @Published var isConnected = false
    @Published var isAuthorizing = false
    @Published var workspaceName: String?
    @Published var statusText = "未连接"
    @Published var syncEnabled = false
    @Published var parentPageId = ""
    @Published var parentPageTitle = ""
    @Published var availablePages: [NotionPageSummary] = []
    @Published var isLoadingPages = false
    @Published var healthDatabaseIdOverride = ""
    @Published var errorMessage: String?

    private let oauthService = NotionOAuthService()
    private let pagesService = NotionParentPagesService()

    func loadState() {
        isConnected = NotionTokenStore.isAuthorized
        workspaceName = NotionTokenStore.workspaceName
        syncEnabled = UserDefaults.standard.bool(forKey: "syncEnabled")
        parentPageId = UserDefaults.standard.string(forKey: "parentPageId") ?? ""
        parentPageTitle = UserDefaults.standard.string(forKey: "parentPageTitle") ?? ""
        healthDatabaseIdOverride = UserDefaults.standard.string(forKey: "healthDatabaseIdOverride") ?? ""
        updateStatusText()
    }

    func connect() async {
        isAuthorizing = true
        errorMessage = nil
        do {
            let response = try await oauthService.performFullAuthorization()
            try NotionTokenStore.save(
                accessToken: response.accessToken,
                workspaceId: response.workspaceId,
                workspaceName: response.workspaceName
            )
            isConnected = true
            workspaceName = response.workspaceName
            updateStatusText()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAuthorizing = false
    }

    func disconnect() {
        NotionTokenStore.clear()
        isConnected = false
        workspaceName = nil
        availablePages = []
        parentPageId = ""
        parentPageTitle = ""
        healthDatabaseIdOverride = ""
        UserDefaults.standard.removeObject(forKey: "syncEnabled")
        UserDefaults.standard.removeObject(forKey: "parentPageId")
        UserDefaults.standard.removeObject(forKey: "parentPageTitle")
        UserDefaults.standard.removeObject(forKey: "healthDatabaseIdOverride")
        syncEnabled = false
        updateStatusText()
    }

    func refreshPages() async {
        guard isConnected else { return }
        isLoadingPages = true
        errorMessage = nil
        do {
            availablePages = try await pagesService.listParentPages(savedPageId: parentPageId.isEmpty ? nil : parentPageId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingPages = false
    }

    func selectPage(_ page: NotionPageSummary) {
        parentPageId = page.id
        parentPageTitle = page.title
        UserDefaults.standard.set(page.id, forKey: "parentPageId")
        UserDefaults.standard.set(page.title, forKey: "parentPageTitle")
    }

    func saveSyncEnabled() {
        UserDefaults.standard.set(syncEnabled, forKey: "syncEnabled")
    }

    func saveHealthDatabaseOverride() {
        UserDefaults.standard.set(healthDatabaseIdOverride, forKey: "healthDatabaseIdOverride")
    }

    func resetHealthDatabaseOverride() {
        healthDatabaseIdOverride = ""
        UserDefaults.standard.removeObject(forKey: "healthDatabaseIdOverride")
    }

    private func updateStatusText() {
        if isAuthorizing {
            statusText = "连接中..."
        } else if isConnected {
            statusText = "已连接" + (workspaceName.map { " (\($0))" } ?? "")
        } else {
            statusText = "未连接"
        }
    }
}
