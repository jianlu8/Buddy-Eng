import SwiftUI

struct RootView: View {
    let container: AppContainer
    @ObservedObject private var rootState: RootViewModel

    init(container: AppContainer) {
        self.container = container
        _rootState = ObservedObject(wrappedValue: container.rootState)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppCanvasBackground()

                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .sheet(isPresented: $rootState.showingHistory) {
                NavigationStack {
                    HistoryView(container: container)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    rootState.showingHistory = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $rootState.showingSettings) {
                NavigationStack {
                    SettingsView(container: container)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    rootState.showingSettings = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $rootState.showingPersonalizationPrompt) {
                PersonalizationSheet(container: container)
            }
            .fullScreenCover(isPresented: $rootState.showingCall) {
                CallView(
                    performanceGovernor: container.performanceGovernor,
                    rootState: rootState,
                    orchestrator: container.orchestrator,
                    context: CallPresentationContext.resolve(
                        rootState: rootState,
                        orchestrator: container.orchestrator
                    )
                )
            }
            .sheet(isPresented: $rootState.showingFeedback) {
                if let report = container.orchestrator.latestFeedback {
                    let session = container.orchestrator.activeSession
                    FeedbackView(
                        report: report,
                        mode: session?.mode ?? rootState.launchingMode,
                        character: session.map { CharacterCatalog.profile(for: $0.characterID) },
                        scene: session.map { CharacterCatalog.scene(for: $0.sceneID, characterID: $0.characterID) },
                        scenario: session?.scenarioID.flatMap { scenarioID in
                            guard let session else { return nil }
                            return ScenarioCatalog.preset(for: scenarioID, mode: session.mode)
                        },
                        learningPlan: session?.learningPlanSnapshot,
                        visualStyle: rootState.snapshot.companionSettings.visualStyle,
                        continueThreadAction: session.map { session in
                            {
                                Task { await reopenCall(from: session, preferredScenarioID: session.scenarioID, continuationAnchor: session) }
                            }
                        },
                        replayMissionAction: session.map { session in
                            {
                                Task { await reopenCall(from: session, preferredScenarioID: session.scenarioID, continuationAnchor: session) }
                            }
                        },
                        nextThemeAction: session.map { session in
                            {
                                Task {
                                    await reopenCall(
                                        from: session,
                                        preferredScenarioID: alternateScenarioID(for: session),
                                        continuationAnchor: session
                                    )
                                }
                            }
                        }
                    ) {
                        rootState.showingFeedback = false
                        container.orchestrator.clearLatestFeedback()
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { rootState.globalError != nil },
                set: { newValue in
                    if newValue == false {
                        rootState.globalError = nil
                    }
                })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rootState.globalError ?? "Unknown error")
            }
            .onChange(of: rootState.snapshot.companionSettings) { _, newValue in
                container.syncPerformanceProfile(using: newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                container.syncPerformanceProfile(using: rootState.snapshot.companionSettings)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                container.syncPerformanceProfile(using: rootState.snapshot.companionSettings)
            }
        }
        .environmentObject(container.performanceGovernor)
    }

    @ViewBuilder
    private var content: some View {
        switch rootState.bootstrapState {
        case let .booting(message):
            LaunchBootView(message: message)
        case .ready:
            NavigationStack {
                HomeView(container: container)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        case let .fatalConfigurationError(message):
            FatalConfigurationView(message: message) {
                Task { await container.bootstrap(force: true) }
            }
        }
    }

    private func reopenCall(
        from session: ConversationSession,
        preferredScenarioID: String?,
        continuationAnchor: ConversationSession?
    ) async {
        do {
            try await rootState.updateCompanionSettings { settings in
                settings.selectedCharacterID = CharacterCatalog.profile(for: session.characterID).id
                settings.selectedSceneID = CharacterCatalog.scene(for: session.sceneID, characterID: session.characterID).id
                settings.conversationLanguageID = session.languageProfileID
                settings.selectedVoiceBundleID = session.voiceBundleID
                settings.warmupCompleted = true
            }
            rootState.showingFeedback = false
            container.orchestrator.clearLatestFeedback()
            await rootState.startCall(
                session.mode,
                preferredScenarioID: preferredScenarioID,
                continuationAnchor: continuationAnchor
            )
        } catch {
            rootState.globalError = error.localizedDescription
        }
    }

    private func alternateScenarioID(for session: ConversationSession) -> String? {
        let presets = ScenarioCatalog.presets(for: session.mode)
        guard presets.isEmpty == false else { return session.scenarioID }

        if let currentID = session.scenarioID,
           let currentIndex = presets.firstIndex(where: { $0.id == currentID }) {
            return presets[(currentIndex + 1) % presets.count].id
        }

        return ScenarioCatalog.recommended(
            for: rootState.snapshot.learnerProfile,
            mode: session.mode
        ).id
    }
}

private struct LaunchBootView: View {
    let message: String

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .frame(width: 150, height: 178)
                    .shadow(color: .black.opacity(0.08), radius: 24, y: 12)

                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Color(red: 0.22, green: 0.19, blue: 0.24))
            }

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
