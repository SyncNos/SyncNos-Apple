import SwiftUI

@main
struct SyncNosForHealthApp: App {
    @State private var debugURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    debugURL = url
                }
        }
    }
}

private struct ContentView: View {
    var body: some View {
        Text("SyncNos Health")
    }
}
