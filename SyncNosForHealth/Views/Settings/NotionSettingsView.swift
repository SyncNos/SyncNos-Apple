import SwiftUI
import Observation

struct NotionSettingsView: View {
    var settings: NotionSettingsViewModel

    var body: some View {
        @Bindable var settings = settings

        List {
            Section("Notion OAuth") {
                HStack {
                    Text("状态")
                    Spacer()
                    Text(settings.statusText)
                        .foregroundStyle(.secondary)
                }

                if settings.isConnected {
                    Button("断开连接", role: .destructive) {
                        settings.disconnect()
                    }
                } else {
                    Button("连接 Notion") {
                        Task { await settings.connect() }
                    }
                    .disabled(settings.isAuthorizing)
                }

                if let error = settings.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("同步到 Notion", isOn: $settings.syncEnabled)
                    .onChange(of: settings.syncEnabled) {
                        settings.saveSyncEnabled()
                    }
            }

            Section("父页面") {
                if settings.availablePages.isEmpty {
                    Text(settings.parentPageTitle.isEmpty ? "未选择" : settings.parentPageTitle)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("父页面", selection: $settings.parentPageId) {
                        ForEach(settings.availablePages) { page in
                            Text(page.title).tag(page.id)
                        }
                    }
                    .onChange(of: settings.parentPageId) {
                        if let page = settings.availablePages.first(where: { $0.id == settings.parentPageId }) {
                            settings.selectPage(page)
                        }
                    }
                }

                Button {
                    Task { await settings.refreshPages() }
                } label: {
                    HStack {
                        Text("刷新页面列表")
                        if settings.isLoadingPages {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!settings.isConnected || settings.isLoadingPages)
            }

            Section {
                DisclosureGroup("高级选项") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("健康数据库 ID 覆盖")
                            .font(.subheadline)
                        TextField("35cbe9d6-386a-8142-8665-ed2d90d9970c", text: $settings.healthDatabaseIdOverride)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.healthDatabaseIdOverride) {
                                settings.saveHealthDatabaseOverride()
                            }
                        Button("重置", role: .destructive) {
                            settings.resetHealthDatabaseOverride()
                        }
                        Text("填写后直接使用该数据库；清空后恢复按父页面自动复用/创建")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Notion 设置")
        .onAppear {
            settings.loadState()
            if settings.isConnected, settings.availablePages.isEmpty, !settings.isLoadingPages {
                Task { await settings.refreshPages() }
            }
        }
    }
}
