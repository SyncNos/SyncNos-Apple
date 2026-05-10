import SwiftUI

@main
struct SyncNosForHealthApp: App {
    @State private var settings = NotionSettingsViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink("睡眠查看") {
                        SleepDayScene(settings: settings)
                    }
                    NavigationLink("Notion 设置") {
                        NotionSettingsView(settings: settings)
                    }
                }
                .navigationTitle("SyncNos Health")
            }
            .onAppear {
                settings.loadState()
            }
        }
    }
}
