import SwiftUI

@main
struct EnglishBuddyApp: App {
    @State private var container: AppContainer?
    @State private var startupTaskInFlight = false

    init() {
        StartupTrace.reset()
        StartupTrace.mark("EnglishBuddyApp.init")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView(container: container)
                } else {
                    AppStartupPlaceholderView()
                }
            }
            .task {
                await Task.yield()
                await Task.yield()
                await ensureContainerReady()
            }
        }
    }

    @MainActor
    private func ensureContainerReady() async {
        guard startupTaskInFlight == false else { return }
        guard container == nil else { return }

        StartupTrace.mark("ensureContainerReady.begin")
        startupTaskInFlight = true
        defer { startupTaskInFlight = false }

        let bootstrappedContainer = AppContainer.bootstrap()
        StartupTrace.mark("ensureContainerReady.containerConstructed")
        container = bootstrappedContainer
        await bootstrappedContainer.bootstrap()
        StartupTrace.mark("ensureContainerReady.containerBootstrapped")
    }
}

private struct AppStartupPlaceholderView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.95, blue: 0.90),
                    Color(red: 1.0, green: 0.98, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                        .frame(width: 112, height: 132)
                        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)

                    Image(systemName: "person.crop.rectangle.stack.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(Color(red: 0.22, green: 0.19, blue: 0.24))
                }

                Text("EnglishBuddy")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.20))

                Text("Starting your local coach")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)

                ProgressView()
                    .tint(Color(red: 0.96, green: 0.42, blue: 0.26))
                    .scaleEffect(1.15)
            }
            .padding(28)
        }
        .onAppear {
            StartupTrace.mark("AppStartupPlaceholderView.onAppear")
        }
    }
}
