import SwiftUI
import Observation
import os

@MainActor
@Observable
final class SleepDayViewModel {
    var selectedDate = Date()
    var sleepData: SleepDayData?
    var isLoading = false
    var isSyncing = false
    var errorMessage: String?
    var syncSuccess = false

    private let timelineService = SleepTimelineService()
    private let dbService = NotionHealthDatabaseService()
    private let upsertService = NotionHealthDailyUpsertService()

    func loadTimeline() async {
        isLoading = true
        errorMessage = nil
        do {
            sleepData = try await timelineService.fetchSleepTimeline(for: selectedDate)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func syncToNotion(settings: NotionSettingsViewModel) async {
        guard let sleepData, !isSyncing else { return }
        guard settings.isConnected, settings.syncEnabled else { return }

        isSyncing = true
        errorMessage = nil
        syncSuccess = false

        let traceId = UUID()
        let workspace = NotionTokenStore.workspaceName ?? "-"
        AppLog.ui.info("syncToNotion start trace=\(traceId.uuidString, privacy: .public) date=\(String(describing: self.selectedDate), privacy: .public) workspace=\(workspace, privacy: .public)")
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: selectedDate)

            let parentPageId = settings.parentPageId
            let overrideId = settings.healthDatabaseIdOverride.isEmpty ? nil : settings.healthDatabaseIdOverride

            guard !parentPageId.isEmpty || overrideId != nil else {
                throw NSError(domain: "SleepDayViewModel", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "请先在设置中选择父页面或填写数据库 ID"])
            }

            let databaseId = try await dbService.ensureDatabase(
                parentPageId: parentPageId,
                overrideId: overrideId,
                traceId: traceId
            )

            try await upsertService.upsert(
                databaseId: databaseId.id,
                titlePropertyName: databaseId.titlePropertyName,
                date: dateStr,
                totalSleepMin: sleepData.totalSleepMinutes,
                traceId: traceId
            )

            syncSuccess = true
            AppLog.ui.info("syncToNotion success trace=\(traceId.uuidString, privacy: .public) databaseId=\(databaseId.id, privacy: .private(mask: .hash)) date=\(dateStr, privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ui.error("syncToNotion failed trace=\(traceId.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
        isSyncing = false
    }

    var canSync: Bool {
        guard let sleepData else { return false }
        return sleepData.totalSleepMinutes > 0
    }
}

struct SleepDayScene: View {
    var settings: NotionSettingsViewModel
    @State private var vm = SleepDayViewModel()

    var body: some View {
        @Bindable var vm = vm

        VStack(spacing: 16) {
            DatePicker("选择日期", selection: $vm.selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .onChange(of: vm.selectedDate) {
                    Task { await vm.loadTimeline() }
                }

            if vm.isLoading {
                ProgressView("加载睡眠数据...")
            } else if let data = vm.sleepData {
                SleepTimelineChart(data: data)

                Button {
                    Task { await vm.syncToNotion(settings: settings) }
                } label: {
                    HStack {
                        if vm.isSyncing {
                            ProgressView()
                        }
                        Text(vm.isSyncing ? "同步中..." : "同步到 Notion")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.isConnected || !settings.syncEnabled || vm.isSyncing || !vm.canSync)

                if vm.syncSuccess {
                    Text("同步成功")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            } else {
                Text("无睡眠数据")
                    .foregroundStyle(.secondary)
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("睡眠详情")
        .task {
            await vm.loadTimeline()
        }
    }
}
