import SwiftUI

@main
struct SyncNosForHealthApp: App {
    @StateObject private var settings = NotionSettingsViewModel()
    @State private var debugURL: URL?

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink("睡眠查看") {
                        SleepDayScene(settings: settings)
                    }
                    NavigationLink("Notion 设置") {
                        NotionSettingsView()
                    }
                }
                .navigationTitle("SyncNos Health")
            }
            .onOpenURL { url in
                debugURL = url
            }
            .onAppear {
                settings.loadState()
            }
        }
    }
}
