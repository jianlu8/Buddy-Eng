import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppCanvasBackground()

                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .sheet(isPresented: $container.rootState.showingHistory) {
                NavigationStack {
                    HistoryView()
                        .environmentObject(container)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    container.rootState.showingHistory = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $container.rootState.showingSettings) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(container)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    container.rootState.showingSettings = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $container.rootState.showingPersonalizationPrompt) {
                PersonalizationSheet()
                    .environmentObject(container)
            }
            .fullScreenCover(isPresented: $container.rootState.showingCall) {
                CallView()
                    .environmentObject(container)
            }
            .sheet(isPresented: $container.rootState.showingFeedback) {
                if let report = container.orchestrator.latestFeedback {
                    FeedbackView(
                        report: report,
                        mode: container.orchestrator.activeSession?.mode ?? container.rootState.launchingMode
                    ) {
                        container.rootState.showingFeedback = false
                        container.orchestrator.clearLatestFeedback()
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { container.rootState.globalError != nil },
                set: { newValue in
                    if newValue == false {
                        container.rootState.globalError = nil
                    }
                })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(container.rootState.globalError ?? "Unknown error")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch container.rootState.bootstrapState {
        case let .booting(message):
            LaunchBootView(message: message)
        case .ready:
            NavigationStack {
                HomeView()
                    .environmentObject(container)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        case let .fatalConfigurationError(message):
            FatalConfigurationView(message: message) {
                Task { await container.bootstrap(force: true) }
            }
        }
    }
}

private struct LaunchBootView: View {
    let message: String

    private var character: CharacterProfile {
        CharacterCatalog.flagship
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            MiraAvatarView(
                state: .thinking,
                audioLevel: 0.08,
                emphasis: .hero,
                characterID: character.id,
                sceneID: character.defaultSceneID
            )
                .frame(width: 260, height: 320)

            VStack(spacing: 10) {
                Text("EnglishBuddy")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.20))
                Text(message)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Loading your built-in coach and restoring local memory.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.85))
            }

            ProgressView()
                .tint(Color(red: 0.96, green: 0.42, blue: 0.26))
                .scaleEffect(1.2)

            Spacer()
        }
        .padding(28)
    }
}

private struct FatalConfigurationView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(red: 0.86, green: 0.26, blue: 0.19))

            VStack(spacing: 12) {
                Text("EnglishBuddy Can't Start")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.20))
                Text(message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Reinstall the app package that includes the built-in Gemma 4 E2B model. If it keeps happening, rebuild from Xcode and install again.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 420)

            Button("Retry Validation", action: retryAction)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.96, green: 0.42, blue: 0.26))

            Spacer()
        }
        .padding(28)
    }
}

struct AppCanvasBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.95, blue: 0.90),
                Color(red: 1.0, green: 0.98, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
