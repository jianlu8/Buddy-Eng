import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var container: AppContainer

    private var snapshot: MemorySnapshot { container.rootState.snapshot }
    private var settings: CompanionSettings { snapshot.companionSettings }
    private var selectedCharacter: CharacterProfile { CharacterCatalog.profile(for: settings.selectedCharacterID) }
    private var selectedScene: CharacterScene {
        CharacterCatalog.scene(for: settings.selectedSceneID, characterID: selectedCharacter.id)
    }
    private var recommendedScenario: ScenarioPreset {
        ScenarioCatalog.recommended(for: snapshot.learnerProfile, mode: container.rootState.selectedMode)
    }
    private var learningPlan: LearningFocusPlan {
        LearningFocusPlan.suggested(
            learner: snapshot.learnerProfile,
            scenario: recommendedScenario,
            mode: container.rootState.selectedMode,
            vocabulary: snapshot.vocabulary
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header

                CharacterStageCard(
                    snapshot: snapshot,
                    character: selectedCharacter,
                    scene: selectedScene,
                    scenario: recommendedScenario,
                    learningPlan: learningPlan,
                    readiness: container.modelManager.activeModelReadiness,
                    modelName: container.modelManager.selectedModel.displayName,
                    selectedMode: Binding(
                        get: { container.rootState.selectedMode },
                        set: { container.rootState.selectedMode = $0 }
                    ),
                    startupState: container.rootState.callStartupState,
                    startAction: {
                        Task { await container.rootState.startCall(container.rootState.selectedMode) }
                    },
                    dismissRecovery: {
                        container.rootState.clearCallRecoveryState()
                    }
                )

                CharacterRail(
                    selectedCharacterID: selectedCharacter.id,
                    profiles: CharacterCatalog.profiles
                ) { profile in
                    Task { await updateCharacterSelection(profile.id) }
                }

                SceneAndMissionPanel(
                    scene: selectedScene,
                    availableScenes: CharacterCatalog.availableScenes(for: selectedCharacter.id),
                    selectedSceneID: selectedScene.id,
                    scenario: recommendedScenario,
                    learningPlan: learningPlan,
                    onSelectScene: { scene in
                        Task { await updateSceneSelection(scene.id) }
                    }
                )

                if needsPersonalization {
                    PersonalizationPromptCard {
                        container.rootState.showingPersonalizationPrompt = true
                    }
                }

                OfflineConfidenceCard(
                    descriptor: container.modelManager.selectedModel,
                    record: container.modelManager.selectedRecord,
                    settings: settings,
                    learner: snapshot.learnerProfile
                )

                if snapshot.sessions.isEmpty == false {
                    SessionHighlightsCard(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(Color.clear)
        .navigationBarHidden(true)
        .task {
            await container.rootState.refresh()
        }
    }

    private var needsPersonalization: Bool {
        let profile = snapshot.learnerProfile
        return profile.preferredName.isEmpty || profile.learningGoal.isEmpty || settings.warmupCompleted == false
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EnglishBuddy")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.13, blue: 0.20))
                Text("Offline video-call English practice with a character that remembers your pace.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color(red: 0.35, green: 0.32, blue: 0.38))
            }

            Spacer(minLength: 12)

            HeaderIconButton(systemImage: "book.pages") {
                container.rootState.showingHistory = true
            }

            HeaderIconButton(systemImage: "slider.horizontal.3") {
                container.rootState.showingSettings = true
            }
        }
    }

    private func updateCharacterSelection(_ characterID: String) async {
        do {
            let defaultScene = CharacterCatalog.defaultScene(for: characterID)
            try await container.memoryStore.updateCompanionSettings { settings in
                settings.selectedCharacterID = characterID
                settings.selectedSceneID = defaultScene.id
                settings.warmupCompleted = true
            }
            await container.rootState.refresh()
        } catch {
            container.rootState.globalError = error.localizedDescription
        }
    }

    private func updateSceneSelection(_ sceneID: String) async {
        do {
            try await container.memoryStore.updateCompanionSettings { settings in
                settings.selectedSceneID = sceneID
                settings.warmupCompleted = true
            }
            await container.rootState.refresh()
        } catch {
            container.rootState.globalError = error.localizedDescription
        }
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.24))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.94))
                        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CharacterStageCard: View {
    let snapshot: MemorySnapshot
    let character: CharacterProfile
    let scene: CharacterScene
    let scenario: ScenarioPreset
    let learningPlan: LearningFocusPlan
    let readiness: ActiveModelReadiness
    let modelName: String
    @Binding var selectedMode: ConversationMode
    let startupState: CallStartupState
    let startAction: () -> Void
    let dismissRecovery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        StatusChip(text: scene.title, tint: Color.white.opacity(0.16), foreground: .white)
                        StatusChip(text: readinessLabel, tint: readinessTint, foreground: readinessForeground)
                    }

                    Text(character.displayName)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text(character.heroHeadline)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.94))

                    Text(character.roleDescription)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VideoCompanionPreview(character: character, scene: scene)
                    .frame(width: 150, height: 210)
            }

            modePicker

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(snapshot.learnerProfile.cefrEstimate.rawValue, systemImage: "chart.bar.xaxis")
                    Spacer()
                    Label(modeSummary, systemImage: selectedMode == .chat ? "phone.fill" : "graduationcap.fill")
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

                StageCalloutCard(
                    title: scenario.title,
                    subtitle: scenario.summary,
                    accent: .white.opacity(0.16)
                )

                StageCalloutCard(
                    title: learningPlan.title,
                    subtitle: learningPlan.mission,
                    footnote: learningPlan.successSignal,
                    accent: Color.black.opacity(0.14)
                )
            }

            startButton

            Text(readinessFootnote)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            if case let .recoverableFailure(_, message, suggestedAction) = startupState {
                RecoveryCard(message: message, suggestedAction: suggestedAction, dismissAction: dismissRecovery)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(backgroundGradient)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: 42, y: -58)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var backgroundGradient: LinearGradient {
        switch scene.lightingStyle {
        case "golden":
            return LinearGradient(
                colors: [Color(red: 0.16, green: 0.29, blue: 0.46), Color(red: 0.90, green: 0.43, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case "neutral":
            return LinearGradient(
                colors: [Color(red: 0.18, green: 0.22, blue: 0.33), Color(red: 0.56, green: 0.46, blue: 0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color(red: 0.11, green: 0.15, blue: 0.32), Color(red: 0.43, green: 0.18, blue: 0.39)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var modeSummary: String {
        selectedMode == .chat ? "Companion call" : "Focused coaching"
    }

    private var readinessLabel: String {
        if case .ready = readiness {
            return "Ready Offline"
        }
        return "Attention Needed"
    }

    private var readinessTint: Color {
        if case .ready = readiness {
            return Color.green.opacity(0.2)
        }
        return Color.red.opacity(0.18)
    }

    private var readinessForeground: Color {
        if case .ready = readiness {
            return Color(red: 0.79, green: 1.0, blue: 0.84)
        }
        return Color(red: 1.0, green: 0.88, blue: 0.84)
    }

    private var readinessFootnote: String {
        if case let .unavailable(message) = readiness {
            return message
        }
        return "\(modelName) is loaded locally. Your character, scene, and mission stay available even without a network connection."
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(ConversationMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text(mode.subtitle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(selectedMode == mode ? 0.86 : 0.66))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selectedMode == mode ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(selectedMode == mode ? 0.28 : 0.12), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var startButton: some View {
        Button(action: startAction) {
            HStack(spacing: 12) {
                if case .starting = startupState {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: selectedMode == .chat ? "video.fill" : "sparkles.rectangle.stack.fill")
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedMode == .chat ? "Start Video Call" : "Start Guided Call")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(buttonSubtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .opacity(isStarting ? 0.78 : 1)
    }

    private var buttonSubtitle: String {
        if case let .starting(message) = startupState {
            return message
        }
        return selectedMode == .chat
            ? "Natural turn-taking, easy interruptions, lighter correction"
            : "One mission, sharper prompts, clearer post-call coaching"
    }

    private var isStarting: Bool {
        if case .starting = startupState {
            return true
        }
        return false
    }
}

private struct StatusChip: View {
    let text: String
    let tint: Color
    let foreground: Color

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(tint))
    }
}

private struct StageCalloutCard: View {
    let title: String
    let subtitle: String
    var footnote: String? = nil
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
            if let footnote, footnote.isEmpty == false {
                Text(footnote)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(accent)
        )
    }
}

private struct VideoCompanionPreview: View {
    let character: CharacterProfile
    let scene: CharacterScene

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(sceneGradient)

            VStack(spacing: 10) {
                HStack {
                    Text("LIVE")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.26)))
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Spacer()

                CharacterStageView(
                    state: .idle,
                    audioLevel: 0.06,
                    emphasis: .hero,
                    characterID: character.id,
                    sceneID: scene.id
                )
                    .frame(width: 116, height: 150)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(Color.black.opacity(0.18))
                            .frame(width: 86, height: 14)
                            .blur(radius: 10)
                            .offset(y: 10)
                    }

                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(character.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Text(scene.ambienceDescription)
                            .font(.system(.caption2, design: .rounded))
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var sceneGradient: LinearGradient {
        switch scene.backdropStyle {
        case "library-depth":
            return LinearGradient(
                colors: [Color(red: 0.25, green: 0.23, blue: 0.22), Color(red: 0.43, green: 0.38, blue: 0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
        case "city-bokeh":
            return LinearGradient(
                colors: [Color(red: 0.12, green: 0.18, blue: 0.32), Color(red: 0.41, green: 0.19, blue: 0.39)],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            return LinearGradient(
                colors: [Color(red: 0.36, green: 0.51, blue: 0.68), Color(red: 0.96, green: 0.61, blue: 0.46)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct CharacterRail: View {
    let selectedCharacterID: String
    let profiles: [CharacterProfile]
    let onSelect: (CharacterProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose Your Companion")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.22))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(profiles) { profile in
                        Button {
                            onSelect(profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(profile.displayName)
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.20))
                                Text(profile.heroHeadline)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                Text(profile.speakingStyle)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color(red: 0.46, green: 0.40, blue: 0.36))
                                    .lineLimit(3)
                            }
                            .frame(width: 184, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(profile.id == selectedCharacterID ? Color(red: 0.99, green: 0.93, blue: 0.88) : Color.white.opacity(0.94))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(profile.id == selectedCharacterID ? Color(red: 0.92, green: 0.42, blue: 0.27) : Color.black.opacity(0.06), lineWidth: profile.id == selectedCharacterID ? 1.5 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct SceneAndMissionPanel: View {
    let scene: CharacterScene
    let availableScenes: [CharacterScene]
    let selectedSceneID: String
    let scenario: ScenarioPreset
    let learningPlan: LearningFocusPlan
    let onSelectScene: (CharacterScene) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Call Setup")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text(scenario.suggestedReplyLength)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0.46, green: 0.42, blue: 0.38))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Scene")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.22, blue: 0.28))

                HStack(spacing: 10) {
                    ForEach(availableScenes) { item in
                        Button {
                            onSelectScene(item)
                        } label: {
                            SceneSelectionChip(title: item.title, isSelected: item.id == selectedSceneID)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(scene.ambienceDescription)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Recommended Mission")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.22, blue: 0.28))

                Text(scenario.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))

                Text(scenario.summary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)

                Label(learningPlan.checkpoint, systemImage: "flag.pattern.checkered")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.46, green: 0.42, blue: 0.38))

                if learningPlan.pronunciationFocus.isEmpty == false {
                    HStack(spacing: 8) {
                        ForEach(learningPlan.pronunciationFocus, id: \.self) { word in
                            Text(word)
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(Color(red: 0.17, green: 0.39, blue: 0.33))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color(red: 0.88, green: 0.96, blue: 0.92)))
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.94))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }
}

private struct SceneSelectionChip: View {
    let title: String
    let isSelected: Bool

    private var foreground: Color {
        isSelected ? .white : Color(red: 0.25, green: 0.22, blue: 0.28)
    }

    private var background: Color {
        isSelected ? Color(red: 0.92, green: 0.42, blue: 0.27) : Color(red: 0.95, green: 0.92, blue: 0.88)
    }

    var body: some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(background))
    }
}

private struct PersonalizationPromptCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish Your Quick Start")
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text("Set your name, speaking goal, and preferred companion so every call feels more personal from the first sentence.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            Button("Open quick setup", action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.96, green: 0.42, blue: 0.26))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }
}

private struct RecoveryCard: View {
    let message: String
    let suggestedAction: String
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Call could not start", systemImage: "exclamationmark.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                Spacer()
                Button("Dismiss", action: dismissAction)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            Text(suggestedAction)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.16))
        )
    }
}

private struct OfflineConfidenceCard: View {
    let descriptor: ModelDescriptor
    let record: ModelInstallationRecord
    let settings: CompanionSettings
    let learner: LearnerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Offline Stack")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text(record.isReadyForInference ? "Ready" : "Unavailable")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(record.isReadyForInference ? .green : .red)
            }

            Text("\(descriptor.displayName) is bundled locally. Character choice, scene, speech pace, and recent memory all load from the device.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                FactPill(title: settings.allowChineseHints ? "Chinese hints on" : "English only", icon: "character.bubble")
                FactPill(title: "Speech rate \(String(format: "%.2f", settings.speechRate))", icon: "speedometer")
                FactPill(title: learner.preferredName.isEmpty ? "Anonymous profile" : learner.preferredName, icon: "person.fill")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }
}

private struct FactPill: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Color(red: 0.30, green: 0.28, blue: 0.34))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(red: 0.96, green: 0.94, blue: 0.91)))
    }
}

private struct SessionHighlightsCard: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent Momentum")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text("\(snapshot.sessions.count) calls")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(snapshot.sessions.prefix(2))) { session in
                let character = CharacterCatalog.profile(for: session.characterID)
                let scenario = ScenarioCatalog.preset(for: session.scenarioID, mode: session.mode)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(character.displayName) • \(session.mode.title)")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Text(scenario.title)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color(red: 0.47, green: 0.42, blue: 0.38))
                        }
                        Spacer()
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(session.summary.isEmpty ? "This call is stored locally and ready for review." : session.summary)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)

                    if let goalSummary = session.feedbackReport?.goalCompletionSummary, goalSummary.isEmpty == false {
                        Text(goalSummary)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(red: 0.31, green: 0.28, blue: 0.34))
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }
}
