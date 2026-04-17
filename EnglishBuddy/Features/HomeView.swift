import SwiftUI

struct HomeView: View {
    let container: AppContainer
    @ObservedObject private var rootState: RootViewModel
    @State private var didAttemptDebugAutoStart = false
    @State private var showingCustomization = false

    init(container: AppContainer) {
        self.container = container
        _rootState = ObservedObject(wrappedValue: container.rootState)
    }

    private var snapshot: MemorySnapshot { rootState.snapshot }
    private var settings: CompanionSettings { snapshot.companionSettings }
    private var selectedCharacter: CharacterProfile { CharacterCatalog.profile(for: settings.selectedCharacterID) }
    private var selectedScene: CharacterScene {
        CharacterCatalog.scene(for: settings.selectedSceneID, characterID: selectedCharacter.id)
    }
    private var selectedVoiceBundle: VoiceBundle {
        VoiceCatalog.bundle(
            for: settings.selectedVoiceBundleID,
            characterID: selectedCharacter.id,
            languageID: settings.conversationLanguageID
        )
    }
    private var conversationLanguage: LanguageProfile {
        LanguageCatalog.profile(for: settings.conversationLanguageID)
    }
    private var explanationLanguage: LanguageProfile {
        LanguageCatalog.profile(for: settings.explanationLanguageID)
    }
    private var recentThreadState: ConversationThreadState? {
        recentSession.flatMap { session in
            snapshot.threadStates.first(where: { $0.id == session.continuationThreadID })
        }
    }
    private var recommendedScenario: ScenarioPreset {
        if let recentSession, recentSession.mode == rootState.selectedMode {
            return ScenarioCatalog.preset(for: recentSession.scenarioID, mode: rootState.selectedMode)
        }
        return ScenarioCatalog.recommended(for: snapshot.learnerProfile, mode: rootState.selectedMode)
    }
    private var learningPlan: LearningFocusPlan {
        if let recentSession, recentSession.mode == rootState.selectedMode {
            return LearningFocusPlan.continued(
                learner: snapshot.learnerProfile,
                scenario: recommendedScenario,
                mode: rootState.selectedMode,
                vocabulary: snapshot.vocabulary,
                previousSession: recentSession
            )
        }
        return LearningFocusPlan.suggested(
            learner: snapshot.learnerProfile,
            scenario: recommendedScenario,
            mode: rootState.selectedMode,
            vocabulary: snapshot.vocabulary
        )
    }
    private var scenarioPresets: [ScenarioPreset] {
        ScenarioCatalog.presets(for: rootState.selectedMode)
    }
    private var recentSession: ConversationSession? {
        snapshot.sessions
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
            .first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                header

                CharacterStageCard(
                    character: selectedCharacter,
                    scene: selectedScene,
                    scenario: recommendedScenario,
                    learningPlan: learningPlan,
                    visualStyle: settings.visualStyle,
                    selectedMode: Binding(
                        get: { rootState.selectedMode },
                        set: { rootState.selectedMode = $0 }
                    ),
                    startupState: rootState.callStartupState,
                    startAction: {
                        Task { await rootState.startCall(rootState.selectedMode) }
                    },
                    dismissRecovery: {
                        rootState.clearCallRecoveryState()
                    }
                )

                if let recentSession {
                    AppSectionHeader(
                        eyebrow: "Resume",
                        title: "Pick up the last thread",
                        subtitle: "Jump back into the most recent call without reopening the whole archive."
                    )
                    ContinueConversationCard(session: recentSession, threadState: recentThreadState) {
                        Task { await continueSession(recentSession) }
                    }
                }

                AppSectionHeader(
                    eyebrow: rootState.selectedMode == .chat ? "Explore" : "Guided practice",
                    title: rootState.selectedMode == .chat ? "Try another conversation angle" : "Choose a sharper guided activity",
                    subtitle: rootState.selectedMode == .chat
                        ? "These are lighter theme switches for when you want a fresh scene, not a different product flow."
                        : "Keep Tutor focused: one mission, one activity, one clear next step."
                )
                ScenarioLaunchRail(
                    mode: rootState.selectedMode,
                    presets: scenarioPresets,
                    recommendedScenarioID: recommendedScenario.id,
                    isBusy: {
                        if case .starting = rootState.callStartupState {
                            return true
                        }
                        return false
                    }(),
                    startAction: { scenario in
                        Task { await startScenario(scenario) }
                    }
                )

                CustomizationDock(
                    isExpanded: $showingCustomization,
                    selectedCharacterID: selectedCharacter.id,
                    profiles: CharacterCatalog.selectableProfiles,
                    scene: selectedScene,
                    availableScenes: CharacterCatalog.availableScenes(for: selectedCharacter.id),
                    selectedSceneID: selectedScene.id,
                    visualStyle: settings.visualStyle,
                    voiceBundle: selectedVoiceBundle,
                    conversationLanguage: conversationLanguage,
                    explanationLanguage: explanationLanguage,
                    scenario: recommendedScenario,
                    learningPlan: learningPlan,
                    onSelectCharacter: { profile in
                        Task { await updateCharacterSelection(profile.id) }
                    },
                    onSelectScene: { scene in
                        Task { await updateSceneSelection(scene.id) }
                    },
                    onSelectVisualStyle: { style in
                        Task { await updateVisualStyleSelection(style) }
                    }
                )

                if needsPersonalization {
                    PersonalizationPromptCard {
                        rootState.showingPersonalizationPrompt = true
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .background(Color.clear)
        .navigationBarHidden(true)
        .task {
            await maybeAutoStartDebugCall()
        }
    }

    private var needsPersonalization: Bool {
        let profile = snapshot.learnerProfile
        return profile.preferredName.isEmpty || profile.learningGoal.isEmpty || settings.warmupCompleted == false
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AppCapsuleBadge(text: "Offline ready", tint: AppTheme.coolAccent)
                    AppCapsuleBadge(
                        text: "English voice calls",
                        tint: AppTheme.warmAccent,
                        foreground: AppTheme.ink,
                        backgroundOpacity: 0.20
                    )
                }

                Text("EnglishBuddy")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Your private English call space. Start fast, keep the same companion, and pick the thread back up any time.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer(minLength: 12)

            HeaderIconButton(systemImage: "book.pages") {
                rootState.showingHistory = true
            }

            HeaderIconButton(systemImage: "slider.horizontal.3") {
                rootState.showingSettings = true
            }
        }
    }

    private func updateCharacterSelection(_ characterID: String) async {
        do {
            let defaultScene = CharacterCatalog.defaultScene(for: characterID)
            try await rootState.updateCompanionSettings { settings in
                settings.selectedCharacterID = characterID
                settings.selectedSceneID = defaultScene.id
                settings.selectedVoiceBundleID = VoiceCatalog.defaultBundle(
                    for: characterID,
                    languageID: settings.conversationLanguageID
                ).id
                settings.warmupCompleted = true
            }
        } catch {
            rootState.globalError = error.localizedDescription
        }
    }

    private func updateSceneSelection(_ sceneID: String) async {
        do {
            try await rootState.updateCompanionSettings { settings in
                settings.selectedSceneID = sceneID
                settings.warmupCompleted = true
            }
        } catch {
            rootState.globalError = error.localizedDescription
        }
    }

    private func updateVisualStyleSelection(_ visualStyle: VideoCallVisualStyle) async {
        do {
            try await rootState.updateCompanionSettings { settings in
                settings.visualStyle = visualStyle
                settings.warmupCompleted = true
            }
        } catch {
            rootState.globalError = error.localizedDescription
        }
    }

    private func continueSession(_ session: ConversationSession) async {
        do {
            try await rootState.updateCompanionSettings { settings in
                settings.selectedCharacterID = CharacterCatalog.profile(for: session.characterID).id
                settings.selectedSceneID = CharacterCatalog.scene(for: session.sceneID, characterID: session.characterID).id
                settings.conversationLanguageID = session.languageProfileID
                settings.selectedVoiceBundleID = session.voiceBundleID
                settings.warmupCompleted = true
            }
            await rootState.startCall(
                session.mode,
                preferredScenarioID: session.scenarioID,
                continuationAnchor: session
            )
        } catch {
            rootState.globalError = error.localizedDescription
        }
    }

    private func startScenario(_ scenario: ScenarioPreset) async {
        await rootState.startCall(
            rootState.selectedMode,
            preferredScenarioID: scenario.id
        )
    }

    private func maybeAutoStartDebugCall() async {
#if DEBUG
        guard didAttemptDebugAutoStart == false else { return }
        didAttemptDebugAutoStart = true

        let rawValue = ProcessInfo.processInfo.environment["ENGLISHBUDDY_DEBUG_AUTO_START_CALL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let rawValue, rawValue.isEmpty == false else { return }
        let mode: ConversationMode = rawValue == "tutor" ? .tutor : .chat

        guard rootState.showingCall == false else { return }
        guard case .idle = rootState.callStartupState else { return }

        await rootState.startCall(mode)
#endif
    }
}

private struct CustomizationDock: View {
    @Binding var isExpanded: Bool
    let selectedCharacterID: String
    let profiles: [CharacterProfile]
    let scene: CharacterScene
    let availableScenes: [CharacterScene]
    let selectedSceneID: String
    let visualStyle: VideoCallVisualStyle
    let voiceBundle: VoiceBundle
    let conversationLanguage: LanguageProfile
    let explanationLanguage: LanguageProfile
    let scenario: ScenarioPreset
    let learningPlan: LearningFocusPlan
    let onSelectCharacter: (CharacterProfile) -> Void
    let onSelectScene: (CharacterScene) -> Void
    let onSelectVisualStyle: (VideoCallVisualStyle) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 18) {
                if profiles.count > 1 {
                    CharacterRail(
                        selectedCharacterID: selectedCharacterID,
                        profiles: profiles,
                        onSelect: onSelectCharacter
                    )
                }

                SceneAndMissionPanel(
                    scene: scene,
                    availableScenes: availableScenes,
                    selectedSceneID: selectedSceneID,
                    visualStyle: visualStyle,
                    voiceBundle: voiceBundle,
                    conversationLanguage: conversationLanguage,
                    explanationLanguage: explanationLanguage,
                    scenario: scenario,
                    learningPlan: learningPlan,
                    onSelectScene: onSelectScene,
                    onSelectVisualStyle: onSelectVisualStyle
                )
            }
            .padding(.top, 14)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Studio & call setup")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Keep the home screen calm. Fine-tune character, scene, and visual direction only when you want to.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "slider.horizontal.3")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.warmAccent)
            }
        }
        .surfaceCard(fill: AppTheme.secondarySurface, shadowOpacity: 0.05)
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(AppTheme.surface)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.hairline, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 14, y: 8)
                )
        }
        .buttonStyle(AppIconChromeButtonStyle())
    }
}

private struct CharacterStageCard: View {
    let character: CharacterProfile
    let scene: CharacterScene
    let scenario: ScenarioPreset
    let learningPlan: LearningFocusPlan
    let visualStyle: VideoCallVisualStyle
    @Binding var selectedMode: ConversationMode
    let startupState: CallStartupState
    let startAction: () -> Void
    let dismissRecovery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heroHeader

            modePicker

            startButton

            focusStack

            if case let .recoverableFailure(_, message, suggestedAction) = startupState {
                RecoveryCard(message: message, suggestedAction: suggestedAction, dismissAction: dismissRecovery)
            }
        }
        .padding(22)
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

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(ConversationMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.title)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Text(mode == .chat ? "Natural back-and-forth" : "Mission-led coaching")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(selectedMode == mode ? 0.86 : 0.66))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selectedMode == mode ? Color.black.opacity(0.30) : Color.black.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(selectedMode == mode ? 0.18 : 0.10), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.mode.\(mode.id)")
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

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .opacity(isStarting ? 0.78 : 1)
        .accessibilityIdentifier("home.startCall")
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

    private var heroHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                heroCopy
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                heroPreview(width: 108, height: 150)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 18) {
                heroCopy

                HStack {
                    Spacer(minLength: 0)
                    heroPreview(width: 124, height: 172)
                }
            }
        }
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    StatusChip(text: scene.title, tint: Color.black.opacity(0.24), foreground: .white)
                    StatusChip(text: visualStyle.title, tint: Color.black.opacity(0.20), foreground: .white.opacity(0.94))
                }
            }

            Text(character.displayName)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            Text(character.heroHeadline)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(3)

            Text(character.roleDescription)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
    }

    private var focusStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedMode == .chat ? "This call opens with" : "Current tutor focus")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.90))

                Spacer()

                Text(scenario.suggestedReplyLength)
                    .font(.system(.caption, design: .rounded, weight: .black))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.22)))
            }

            VStack(alignment: .leading, spacing: 10) {
                StageCalloutCard(
                    title: scenario.title,
                    subtitle: scenario.summary,
                    accent: Color.black.opacity(0.22)
                )

                StageCalloutCard(
                    title: learningPlan.title,
                    subtitle: learningPlan.mission,
                    footnote: learningPlan.successSignal,
                    accent: Color.black.opacity(0.28)
                )
            }
        }
    }

    private func heroPreview(width: CGFloat, height: CGFloat) -> some View {
        VideoCompanionPreview(
            character: character,
            scene: scene,
            visualStyle: visualStyle
        )
        .frame(width: width, height: height)
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
            .background(
                Capsule()
                    .fill(tint)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
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

private struct VideoCompanionPreview: View, Equatable {
    let character: CharacterProfile
    let scene: CharacterScene
    let visualStyle: VideoCallVisualStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(sceneGradient)

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.18), Color.black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )

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

                CharacterStageSurface(
                    character: character,
                    scene: scene,
                    visualStyle: visualStyle,
                    emphasis: .preview,
                    surfaceKind: .quickStartPreview,
                    size: CGSize(width: 116, height: 150),
                    isAnimated: false,
                    showsBackdrop: false,
                    groundShadowWidth: 86
                )

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
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                )
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
    let visualStyle: VideoCallVisualStyle
    let voiceBundle: VoiceBundle
    let conversationLanguage: LanguageProfile
    let explanationLanguage: LanguageProfile
    let scenario: ScenarioPreset
    let learningPlan: LearningFocusPlan
    let onSelectScene: (CharacterScene) -> Void
    let onSelectVisualStyle: (VideoCallVisualStyle) -> Void

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

            VStack(alignment: .leading, spacing: 10) {
                Text("Visual Style")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.22, blue: 0.28))

                HStack(spacing: 10) {
                    ForEach(VideoCallVisualStyle.allCases) { style in
                        Button {
                            onSelectVisualStyle(style)
                        } label: {
                            SceneSelectionChip(title: style.title, isSelected: style == visualStyle)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(visualStyle.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Language Stack")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.22, blue: 0.28))

                HStack(spacing: 10) {
                    SceneSelectionChip(title: conversationLanguage.displayName, isSelected: true)
                    SceneSelectionChip(title: explanationLanguage.displayName, isSelected: true)
                    SceneSelectionChip(title: voiceBundle.displayName, isSelected: true)
                }

                Text("Conversation stays in \(conversationLanguage.displayName). Clarifications can switch to \(explanationLanguage.displayName).")
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
        isSelected ? Color(red: 0.35, green: 0.18, blue: 0.10) : Color(red: 0.25, green: 0.22, blue: 0.28)
    }

    private var background: Color {
        isSelected ? Color(red: 0.99, green: 0.88, blue: 0.78) : Color(red: 0.95, green: 0.92, blue: 0.88)
    }

    var body: some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(background))
            .overlay {
                Capsule()
                    .stroke(
                        isSelected ? Color(red: 0.87, green: 0.41, blue: 0.24) : Color.black.opacity(0.05),
                        lineWidth: isSelected ? 1.25 : 1
                    )
            }
    }
}

private struct ContinueConversationCard: View {
    let session: ConversationSession
    let threadState: ConversationThreadState?
    let continueAction: () -> Void

    private var character: CharacterProfile {
        CharacterCatalog.profile(for: session.characterID)
    }

    private var scene: CharacterScene {
        CharacterCatalog.scene(for: session.sceneID, characterID: session.characterID)
    }

    private var scenarioTitle: String {
        ScenarioCatalog.preset(for: session.scenarioID, mode: session.mode).title
    }

    private var summaryText: String {
        if let continuationCue = threadState?.continuationCue, continuationCue.isEmpty == false {
            return continuationCue
        }
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            return summary
        }
        return session.turns.last?.text ?? "Pick the thread back up from your most recent exchange."
    }

    private var missionText: String? {
        if let nextMission = threadState?.nextMission, nextMission.isEmpty == false {
            return nextMission
        }
        if let mission = session.learningPlanSnapshot?.mission, mission.isEmpty == false {
            return mission
        }
        return nil
    }

    private var durationText: String {
        let totalMinutes = Int(session.duration / 60)
        if totalMinutes > 0 {
            return "\(totalMinutes) min"
        }
        return "<1 min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AppSectionHeader(
                    eyebrow: "Recent thread",
                    title: "Continue last call",
                    subtitle: nil
                )
                Spacer()
                AppCapsuleBadge(
                    text: session.mode.title,
                    tint: AppTheme.warmAccent,
                    foreground: AppTheme.ink,
                    backgroundOpacity: 0.18
                )
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(character.displayName) • \(scenarioTitle)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)

                    Text(summaryText)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CharacterStageSurface(
                    character: character,
                    scene: scene,
                    visualStyle: .natural,
                    emphasis: .preview,
                    surfaceKind: .historyPreview,
                    size: CGSize(width: 92, height: 118),
                    isAnimated: false,
                    showsBackdrop: false,
                    groundShadowWidth: 64,
                    groundShadowHeight: 10,
                    groundShadowBlur: 7
                )
                .frame(width: 92, height: 118)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.90, green: 0.90, blue: 0.94),
                                    Color(red: 0.97, green: 0.94, blue: 0.91)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            if let missionText {
                Text(missionText)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.30, green: 0.28, blue: 0.34))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.94, blue: 0.91))
                    )
            }

            HStack(spacing: 10) {
                AppCapsuleBadge(
                    text: session.startedAt.formatted(date: .abbreviated, time: .shortened),
                    tint: AppTheme.coolAccent,
                    foreground: AppTheme.ink,
                    backgroundOpacity: 0.16
                )

                AppCapsuleBadge(
                    text: "\(session.turns.count) turns",
                    tint: AppTheme.coolAccent,
                    foreground: AppTheme.ink,
                    backgroundOpacity: 0.12
                )

                AppCapsuleBadge(
                    text: durationText,
                    tint: AppTheme.coolAccent,
                    foreground: AppTheme.ink,
                    backgroundOpacity: 0.12
                )
            }

            Button(action: continueAction) {
                HStack(spacing: 10) {
                    Image(systemName: "video.badge.waveform")
                    Text("Resume This Thread")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.92, green: 0.42, blue: 0.27))
                )
            }
            .buttonStyle(.plain)
        }
        .surfaceCard()
    }
}

private struct ScenarioLaunchRail: View {
    let mode: ConversationMode
    let presets: [ScenarioPreset]
    let recommendedScenarioID: String
    let isBusy: Bool
    let startAction: (ScenarioPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(mode == .chat ? "Open a theme" : "Guided activities")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                AppCapsuleBadge(
                    text: mode.title,
                    tint: AppTheme.warmAccent,
                    foreground: AppTheme.ink,
                    backgroundOpacity: 0.18
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(presets) { scenario in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                if scenario.id == recommendedScenarioID {
                                    Text("Recommended")
                                        .font(.system(.caption2, design: .rounded, weight: .black))
                                        .foregroundStyle(Color(red: 0.17, green: 0.39, blue: 0.33))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(Color(red: 0.88, green: 0.96, blue: 0.92)))
                                } else {
                                    Text(mode == .chat ? "Theme" : "Activity")
                                        .font(.system(.caption2, design: .rounded, weight: .black))
                                        .foregroundStyle(Color(red: 0.46, green: 0.42, blue: 0.38))
                                }
                                Spacer()
                                Text(scenario.suggestedReplyLength)
                                    .font(.system(.caption2, design: .rounded, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(scenario.title)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.20))

                            Text(scenario.summary)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            Button {
                                startAction(scenario)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: mode == .chat ? "video.fill" : "figure.mind.and.body")
                                    Text(mode == .chat ? "Start This Theme" : "Start This Activity")
                                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(red: 0.92, green: 0.42, blue: 0.27))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                            .opacity(isBusy ? 0.6 : 1)
                        }
                        .frame(width: 248, alignment: .leading)
                        .surfaceCard(fill: AppTheme.surface, shadowOpacity: 0.05)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(
                                    scenario.id == recommendedScenarioID
                                        ? AppTheme.warmAccent.opacity(0.34)
                                        : AppTheme.hairline,
                                    lineWidth: scenario.id == recommendedScenarioID ? 1.5 : 1
                                )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
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
        .surfaceCard(fill: AppTheme.secondarySurface, shadowOpacity: 0.05)
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
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OfflineConfidenceCard: View {
    let descriptor: ModelDescriptor
    let record: ModelInstallationRecord
    let settings: CompanionSettings
    let learner: LearnerProfile
    let voiceBundle: VoiceBundle
    let conversationLanguage: LanguageProfile
    let explanationLanguage: LanguageProfile

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
                FactPill(title: "\(conversationLanguage.displayName) calls", icon: "globe")
                FactPill(title: "\(explanationLanguage.displayName) help", icon: "character.bubble")
                FactPill(title: voiceBundle.displayName, icon: "speaker.wave.2.fill")
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
