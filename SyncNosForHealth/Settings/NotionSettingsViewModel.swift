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
    private let store = NotionSettingsStore()

    func loadState() {
        isConnected = NotionTokenStore.isAuthorized
        workspaceName = NotionTokenStore.workspaceName
        syncEnabled = store.syncEnabled
        parentPageId = store.parentPageId
        parentPageTitle = store.parentPageTitle
        healthDatabaseIdOverride = store.healthDatabaseIdOverride
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
        store.clear()
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
        store.parentPageId = page.id
        store.parentPageTitle = page.title
    }

    func saveSyncEnabled() {
        store.syncEnabled = syncEnabled
    }

    func saveHealthDatabaseOverride() {
        store.healthDatabaseIdOverride = healthDatabaseIdOverride
    }

    func resetHealthDatabaseOverride() {
        healthDatabaseIdOverride = ""
        store.healthDatabaseIdOverride = ""
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
