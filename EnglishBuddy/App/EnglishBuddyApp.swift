import SwiftUI

@main
struct EnglishBuddyApp: App {
    @StateObject private var container = AppContainer.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .task {
                    await container.bootstrap()
                }
        }
    }
}

