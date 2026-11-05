import SwiftUI

@main
struct TempoTeleApp: App {
    @StateObject private var manager = TelevisionManager()
    @StateObject private var remote = LGTVRemote()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .environmentObject(remote)
        }
    }
}
