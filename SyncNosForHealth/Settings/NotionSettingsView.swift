import SwiftUI

struct NotionSettingsView: View {
    @StateObject private var vm = NotionSettingsViewModel()

    var body: some View {
        List {
            Section("Notion OAuth") {
                HStack {
                    Text("状态")
                    Spacer()
                    Text(vm.statusText)
                        .foregroundStyle(.secondary)
                }

                if vm.isConnected {
                    Button("断开连接", role: .destructive) {
                        vm.disconnect()
                    }
                } else {
                    Button("连接 Notion") {
                        Task { await vm.connect() }
                    }
                    .disabled(vm.isAuthorizing)
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("同步到 Notion", isOn: $vm.syncEnabled)
                    .onChange(of: vm.syncEnabled) { _ in
                        vm.saveSyncEnabled()
                    }
            }

            Section("父页面") {
                if vm.availablePages.isEmpty {
                    Text(vm.parentPageTitle.isEmpty ? "未选择" : vm.parentPageTitle)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("父页面", selection: $vm.parentPageId) {
                        ForEach(vm.availablePages) { page in
                            Text(page.title).tag(page.id)
                        }
                    }
                    .onChange(of: vm.parentPageId) { _ in
                        if let page = vm.availablePages.first(where: { $0.id == vm.parentPageId }) {
                            vm.selectPage(page)
                        }
                    }
                }

                Button {
                    Task { await vm.refreshPages() }
                } label: {
                    HStack {
                        Text("刷新页面列表")
                        if vm.isLoadingPages {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!vm.isConnected || vm.isLoadingPages)
            }

            Section {
                DisclosureGroup("高级选项") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("健康数据库 ID 覆盖")
                            .font(.subheadline)
                        TextField("35cbe9d6-386a-8142-8665-ed2d90d9970c", text: $vm.healthDatabaseIdOverride)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: vm.healthDatabaseIdOverride) { _ in
                                vm.saveHealthDatabaseOverride()
                            }
                        Button("重置", role: .destructive) {
                            vm.resetHealthDatabaseOverride()
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
            vm.loadState()
        }
    }
}
