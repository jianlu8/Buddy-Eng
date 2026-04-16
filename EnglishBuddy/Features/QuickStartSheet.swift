import SwiftUI

struct PersonalizationSheet: View {
    let container: AppContainer
    @ObservedObject private var rootState: RootViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var goal = ""
    @State private var mode: ConversationMode = .chat
    @State private var selectedCharacterID = CharacterCatalog.flagship.id
    @State private var selectedSceneID = CharacterCatalog.flagship.defaultSceneID
    @State private var selectedVoiceBundleID = VoiceCatalog.defaultBundle(
        for: CharacterCatalog.flagship.id,
        languageID: LanguageCatalog.english.id
    ).id
    @State private var conversationLanguageID = LanguageCatalog.english.id
    @State private var explanationLanguageID = LanguageCatalog.simplifiedChinese.id
    @State private var selectedVisualStyle: VideoCallVisualStyle = .natural
    @State private var loadedInitialState = false
    @State private var saving = false

    init(container: AppContainer) {
        self.container = container
        _rootState = ObservedObject(wrappedValue: container.rootState)
    }

    private var selectedCharacter: CharacterProfile { CharacterCatalog.profile(for: selectedCharacterID) }
    private var selectableProfiles: [CharacterProfile] { CharacterCatalog.selectableProfiles }
    private var availableScenes: [CharacterScene] { CharacterCatalog.availableScenes(for: selectedCharacterID) }
    private var selectedScene: CharacterScene { CharacterCatalog.scene(for: selectedSceneID, characterID: selectedCharacterID) }
    private var availableVoiceBundles: [VoiceBundle] { VoiceCatalog.bundles(for: selectedCharacterID, languageID: conversationLanguageID) }
    private var selectedVoiceBundle: VoiceBundle {
        VoiceCatalog.bundle(for: selectedVoiceBundleID, characterID: selectedCharacterID, languageID: conversationLanguageID)
    }
    private var conversationLanguage: LanguageProfile { LanguageCatalog.profile(for: conversationLanguageID) }
    private var explanationLanguage: LanguageProfile { LanguageCatalog.profile(for: explanationLanguageID) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        previewCard
                        characterPicker
                        scenePicker
                        visualStylePicker
                        saveButton
                        secondarySetupPanel
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                guard loadedInitialState == false else { return }
                let snapshot = rootState.snapshot
                name = snapshot.learnerProfile.preferredName
                goal = snapshot.learnerProfile.learningGoal
                mode = snapshot.learnerProfile.preferredMode
                selectedCharacterID = snapshot.companionSettings.selectedCharacterID
                selectedSceneID = snapshot.companionSettings.selectedSceneID
                selectedVoiceBundleID = snapshot.companionSettings.selectedVoiceBundleID
                conversationLanguageID = snapshot.companionSettings.conversationLanguageID
                explanationLanguageID = snapshot.companionSettings.explanationLanguageID
                selectedVisualStyle = snapshot.companionSettings.visualStyle
                loadedInitialState = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start Your First Call")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.13, blue: 0.20))
            Text("Pick the character and stage you want, then save. Personal details, language, and compatibility details stay available underneath when you need them.")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedCharacter.displayName)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                    Text(selectedCharacter.heroHeadline)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(selectedScene.ambienceDescription)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer()

                VideoSetupPreview(
                    character: selectedCharacter,
                    scene: selectedScene,
                    visualStyle: selectedVisualStyle
                )
                    .frame(width: 126, height: 164)
            }

            VStack(alignment: .leading, spacing: 8) {
                SetupFact(text: selectedCharacter.speakingStyle, icon: "waveform")
                SetupFact(text: selectedCharacter.greetingStyle, icon: "video.bubble.left")
                SetupFact(text: selectedScene.title, icon: "sparkles.tv")
                SetupFact(text: selectedVisualStyle.title, icon: "camera.filters")
                SetupFact(text: "\(selectedVoiceBundle.displayName) • \(selectedVoiceBundle.accentLabel)", icon: "speaker.wave.2.fill")
                SetupFact(text: "\(conversationLanguage.displayName) call / \(explanationLanguage.displayName) help", icon: "globe")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.16, green: 0.28, blue: 0.45), Color(red: 0.91, green: 0.43, blue: 0.27)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var characterPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Character")
                .font(.system(.title3, design: .rounded, weight: .bold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(selectableProfiles) { profile in
                        Button {
                            selectedCharacterID = profile.id
                            selectedSceneID = CharacterCatalog.defaultScene(for: profile.id).id
                            selectedVoiceBundleID = VoiceCatalog.defaultBundle(
                                for: profile.id,
                                languageID: conversationLanguageID
                            ).id
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(profile.displayName)
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.20))
                                Text(profile.roleDescription)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            .frame(width: 190, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(profile.id == selectedCharacterID ? Color(red: 0.99, green: 0.93, blue: 0.88) : Color.white.opacity(0.92))
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
        .panelCard()
    }

    private var scenePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scene")
                .font(.system(.title3, design: .rounded, weight: .bold))

            HStack(spacing: 10) {
                ForEach(availableScenes) { scene in
                    Button {
                        selectedSceneID = scene.id
                    } label: {
                        QuickStartSceneCard(
                            title: scene.title,
                            subtitle: scene.lightingStyle.capitalized,
                            isSelected: scene.id == selectedSceneID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(selectedScene.ambienceDescription)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .panelCard()
    }

    private var profileForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learner Profile")
                .font(.system(.title3, design: .rounded, weight: .bold))

            VStack(alignment: .leading, spacing: 8) {
                Text("What should your companion call you?")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                TextField("For example: Hammond", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What speaking result do you want next?")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                TextField("For example: sound calmer in English meetings", text: $goal, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
            }
        }
        .panelCard()
    }

    private var visualStylePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visual Style")
                .font(.system(.title3, design: .rounded, weight: .bold))

            HStack(spacing: 10) {
                ForEach(VideoCallVisualStyle.allCases) { style in
                    Button {
                        selectedVisualStyle = style
                    } label: {
                        QuickStartSceneCard(
                            title: style.title,
                            subtitle: style.subtitle,
                            isSelected: style == selectedVisualStyle
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Pick the look you want the call stage to keep across the app.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .panelCard()
    }

    private var languageSupportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language & Voice")
                .font(.system(.title3, design: .rounded, weight: .bold))

            Picker("Conversation Language", selection: $conversationLanguageID) {
                ForEach(LanguageCatalog.all) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }
            .onChange(of: conversationLanguageID) { _, newValue in
                selectedVoiceBundleID = VoiceCatalog.defaultBundle(
                    for: selectedCharacterID,
                    languageID: newValue
                ).id
            }

            Picker("Explanation Language", selection: $explanationLanguageID) {
                ForEach(LanguageCatalog.all) { profile in
                    Text(profile.displayName).tag(profile.id)
                }
            }

            Picker("Voice / Accent", selection: $selectedVoiceBundleID) {
                ForEach(availableVoiceBundles) { voiceBundle in
                    Text(voiceBundle.displayName).tag(voiceBundle.id)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Reference Accent: \(selectedVoiceBundle.accentLabel)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(selectedVoiceBundle.styleDescription)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .panelCard()
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default Call Style")
                .font(.system(.title3, design: .rounded, weight: .bold))

            HStack(spacing: 10) {
                ForEach(ConversationMode.allCases) { candidate in
                    Button {
                        mode = candidate
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(candidate.title)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Text(candidate.subtitle)
                                .font(.system(.caption, design: .rounded))
                                .lineLimit(3)
                        }
                        .foregroundStyle(mode == candidate ? .white : Color(red: 0.21, green: 0.19, blue: 0.25))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(mode == candidate ? Color(red: 0.25, green: 0.30, blue: 0.44) : Color.white.opacity(0.92))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelCard()
    }

    private var portraitCharacterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photo Character")
                .font(.system(.title3, design: .rounded, weight: .bold))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: CharacterCatalog.primaryPortraitAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(CharacterCatalog.primaryPortraitAvailable ? Color(red: 0.19, green: 0.56, blue: 0.30) : Color(red: 0.80, green: 0.45, blue: 0.17))
                    .font(.system(size: 20, weight: .semibold))

                VStack(alignment: .leading, spacing: 4) {
                    Text(CharacterCatalog.primaryPortraitAvailable ? "Bundled photo character is active" : "Bundled photo character is missing")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text(
                        CharacterCatalog.primaryPortraitAvailable
                            ? "The app now uses the bundled portrait as the default call character across home, preview, and live call views."
                            : "A local portrait photo is required before the release-ready character can render as the main video-call presence."
                    )
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var secondarySetupPanel: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 18) {
                profileForm
                languageSupportPanel
                modePicker
                portraitCharacterPanel
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("More Options")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.20))
                Text("Name, goal, language, default mode, and photo character status stay here so the first setup stays lightweight.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .panelCard()
    }

    private var saveButton: some View {
        Button {
            Task { await savePreferences() }
        } label: {
            HStack {
                if saving {
                    ProgressView()
                        .tint(.white)
                }
                Text(saving ? "Saving..." : "Use This Setup")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.92, green: 0.42, blue: 0.27))
            )
        }
        .buttonStyle(.plain)
        .disabled(saving)
    }

    private func savePreferences() async {
        saving = true
        defer { saving = false }

        let capturedName = name
        let capturedGoal = goal
        let capturedMode = mode
        let capturedCharacterID = selectedCharacterID
        let capturedSceneID = selectedSceneID
        let capturedVoiceBundleID = selectedVoiceBundleID
        let capturedConversationLanguageID = conversationLanguageID
        let capturedExplanationLanguageID = explanationLanguageID
        let capturedVisualStyle = selectedVisualStyle
        do {
            try await rootState.updateLearnerProfile { profile in
                profile.preferredName = capturedName
                profile.learningGoal = capturedGoal
                profile.preferredMode = capturedMode
            }
            try await rootState.updateCompanionSettings { settings in
                settings.selectedCharacterID = capturedCharacterID
                settings.selectedSceneID = capturedSceneID
                settings.selectedVoiceBundleID = capturedVoiceBundleID
                settings.conversationLanguageID = capturedConversationLanguageID
                settings.explanationLanguageID = capturedExplanationLanguageID
                settings.visualStyle = capturedVisualStyle
                settings.allowChineseHints = capturedExplanationLanguageID != LanguageCatalog.english.id
                settings.portraitModeEnabled = CharacterCatalog.primaryPortraitAvailable
                settings.warmupCompleted = true
            }
            rootState.selectedMode = capturedMode
            rootState.showingPersonalizationPrompt = false
            dismiss()
        } catch {
            rootState.globalError = error.localizedDescription
        }
    }
}

private struct QuickStartSceneCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    private var foreground: Color {
        isSelected ? Color(red: 0.35, green: 0.18, blue: 0.10) : Color(red: 0.22, green: 0.20, blue: 0.26)
    }

    private var background: Color {
        isSelected ? Color(red: 0.99, green: 0.88, blue: 0.78) : Color(red: 0.97, green: 0.95, blue: 0.92)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            Text(subtitle)
                .font(.system(.caption2, design: .rounded))
        }
        .foregroundStyle(foreground)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(background)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isSelected ? Color(red: 0.87, green: 0.41, blue: 0.24) : Color.black.opacity(0.05),
                    lineWidth: isSelected ? 1.25 : 1
                )
        }
    }
}

private struct VideoSetupPreview: View, Equatable {
    let character: CharacterProfile
    let scene: CharacterScene
    let visualStyle: VideoCallVisualStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: scene.backdropStyle == "city-bokeh"
                            ? [Color(red: 0.13, green: 0.18, blue: 0.34), Color(red: 0.42, green: 0.20, blue: 0.41)]
                            : [Color(red: 0.36, green: 0.51, blue: 0.68), Color(red: 0.95, green: 0.61, blue: 0.46)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.16), Color.black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    Text("READY")
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.2)))
                    Spacer()
                }
                .padding(10)

                Spacer()

                CharacterStageSurface(
                    character: character,
                    scene: scene,
                    visualStyle: visualStyle,
                    emphasis: .preview,
                    surfaceKind: .quickStartPreview,
                    size: CGSize(width: 96, height: 118),
                    isAnimated: false,
                    showsBackdrop: false,
                    groundShadowWidth: 70,
                    groundShadowHeight: 12,
                    groundShadowBlur: 8
                )

                Spacer()

                Text(character.displayName)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.26)))
                    .padding(.bottom, 10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct SetupFact: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
    }
}

private extension View {
    func panelCard() -> some View {
        padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            }
    }
}

typealias QuickStartSheet = PersonalizationSheet
