import SwiftUI

@main
struct SyncNosForHealthApp: App {
    @State private var debugURL: URL?

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink("Notion 设置") {
                        NotionSettingsView()
                    }
                }
                .navigationTitle("SyncNos Health")
            }
            .onOpenURL { url in
                debugURL = url
            }
        }
    }
}
