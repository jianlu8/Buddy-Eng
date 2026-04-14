import SwiftUI

struct PersonalizationSheet: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var goal = ""
    @State private var mode: ConversationMode = .chat
    @State private var selectedCharacterID = CharacterCatalog.flagship.id
    @State private var selectedSceneID = CharacterCatalog.flagship.defaultSceneID
    @State private var allowChineseHints = true
    @State private var loadedInitialState = false
    @State private var saving = false

    private var selectedCharacter: CharacterProfile { CharacterCatalog.profile(for: selectedCharacterID) }
    private var availableScenes: [CharacterScene] { CharacterCatalog.availableScenes(for: selectedCharacterID) }
    private var selectedScene: CharacterScene { CharacterCatalog.scene(for: selectedSceneID, characterID: selectedCharacterID) }

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
                        profileForm
                        modePicker
                        hintToggle
                        saveButton
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
                let snapshot = container.rootState.snapshot
                name = snapshot.learnerProfile.preferredName
                goal = snapshot.learnerProfile.learningGoal
                mode = snapshot.learnerProfile.preferredMode
                selectedCharacterID = snapshot.companionSettings.selectedCharacterID
                selectedSceneID = snapshot.companionSettings.selectedSceneID
                allowChineseHints = snapshot.companionSettings.allowChineseHints
                loadedInitialState = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Start")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.13, blue: 0.20))
            Text("Set up the companion, scene, and learning goal you want to carry into your offline calls.")
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

                VideoSetupPreview(character: selectedCharacter, scene: selectedScene)
                    .frame(width: 126, height: 164)
            }

            VStack(alignment: .leading, spacing: 8) {
                SetupFact(text: selectedCharacter.speakingStyle, icon: "waveform")
                SetupFact(text: selectedCharacter.greetingStyle, icon: "video.bubble.left")
                SetupFact(text: selectedScene.title, icon: "sparkles.tv")
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
                    ForEach(CharacterCatalog.profiles) { profile in
                        Button {
                            selectedCharacterID = profile.id
                            selectedSceneID = CharacterCatalog.defaultScene(for: profile.id).id
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

    private var hintToggle: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language Support")
                .font(.system(.title3, design: .rounded, weight: .bold))

            Toggle(isOn: $allowChineseHints) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow concise Chinese hints")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text("Keep speaking practice in English, but allow short Chinese clarification when needed.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color(red: 0.92, green: 0.42, blue: 0.27))
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
                Text(saving ? "Saving..." : "Save quick setup")
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
        let capturedAllowChineseHints = allowChineseHints

        do {
            try await container.memoryStore.updateLearnerProfile { profile in
                profile.preferredName = capturedName
                profile.learningGoal = capturedGoal
                profile.preferredMode = capturedMode
            }
            try await container.memoryStore.updateCompanionSettings { settings in
                settings.selectedCharacterID = capturedCharacterID
                settings.selectedSceneID = capturedSceneID
                settings.allowChineseHints = capturedAllowChineseHints
                settings.warmupCompleted = true
            }
            container.rootState.selectedMode = capturedMode
            await container.rootState.refresh()
            container.rootState.showingPersonalizationPrompt = false
            dismiss()
        } catch {
            container.rootState.globalError = error.localizedDescription
        }
    }
}

private struct QuickStartSceneCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    private var foreground: Color {
        isSelected ? .white : Color(red: 0.22, green: 0.20, blue: 0.26)
    }

    private var background: Color {
        isSelected ? Color(red: 0.92, green: 0.42, blue: 0.27) : Color(red: 0.97, green: 0.95, blue: 0.92)
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
    }
}

private struct VideoSetupPreview: View {
    let character: CharacterProfile
    let scene: CharacterScene

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

                CharacterStageView(
                    state: .idle,
                    audioLevel: 0.05,
                    emphasis: .hero,
                    characterID: character.id,
                    sceneID: scene.id
                )
                    .frame(width: 96, height: 118)

                Spacer()

                Text(character.displayName)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
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
