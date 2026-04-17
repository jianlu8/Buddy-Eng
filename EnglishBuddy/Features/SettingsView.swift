import SwiftUI

struct SettingsView: View {
    let container: AppContainer
    @ObservedObject private var rootState: RootViewModel
    @ObservedObject private var modelManager: ModelDownloadManager
    @State private var draftSpeechRate = Double(CompanionSettings.default.speechRate)
    @State private var isEditingSpeechRate = false
    @State private var diagnosticsExpanded = false

    init(container: AppContainer) {
        self.container = container
        _rootState = ObservedObject(wrappedValue: container.rootState)
        _modelManager = ObservedObject(wrappedValue: container.modelManager)
    }

    var body: some View {
        let snapshot = rootState.snapshot
        let settings = snapshot.companionSettings
        let selectedCharacter = CharacterCatalog.profile(for: settings.selectedCharacterID)
        let selectedScene = CharacterCatalog.scene(for: settings.selectedSceneID, characterID: selectedCharacter.id)
        let availableScenes = CharacterCatalog.availableScenes(for: selectedCharacter.id)
        let conversationLanguage = LanguageCatalog.profile(for: settings.conversationLanguageID)
        let explanationLanguage = LanguageCatalog.profile(for: settings.explanationLanguageID)
        let availableVoiceBundles = VoiceCatalog.bundles(for: selectedCharacter.id, languageID: conversationLanguage.id)
        let selectedVoiceBundle = VoiceCatalog.bundle(
            for: settings.selectedVoiceBundleID,
            characterID: selectedCharacter.id,
            languageID: conversationLanguage.id
        )
        let speechRuntimeStatus = container.speechPipeline.runtimeStatus(
            conversationLanguage: conversationLanguage,
            voiceBundle: selectedVoiceBundle
        )

        return ZStack {
            AppCanvasBackground(style: .settings)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    settingsHero(
                        selectedCharacter: selectedCharacter,
                        selectedScene: selectedScene,
                        visualStyle: settings.visualStyle,
                        selectedVoiceBundle: selectedVoiceBundle,
                        conversationLanguage: conversationLanguage,
                        explanationLanguage: explanationLanguage
                    )

                    VStack(alignment: .leading, spacing: 16) {
                        AppSectionHeader(
                            eyebrow: "Companion",
                            title: "Character and scene",
                            subtitle: "Keep the main settings path about who you call, where they appear, and how the session looks."
                        )

                        SettingsControlRow(title: "Character", subtitle: "Choose the on-screen companion for the next call.") {
                            Picker("Character", selection: binding(
                                get: { settings.selectedCharacterID },
                                set: { current, newValue in
                                    current.selectedCharacterID = newValue
                                    current.selectedSceneID = CharacterCatalog.defaultScene(for: newValue).id
                                    current.selectedVoiceBundleID = VoiceCatalog.defaultBundle(
                                        for: newValue,
                                        languageID: current.conversationLanguageID
                                    ).id
                                }
                            )) {
                                ForEach(CharacterCatalog.selectableProfiles) { profile in
                                    Text(profile.displayName).tag(profile.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        SettingsControlRow(title: "Scene", subtitle: "Adjust the call backdrop without changing the character.") {
                            Picker("Scene", selection: binding(
                                get: { settings.selectedSceneID },
                                set: { current, newValue in
                                    current.selectedSceneID = newValue
                                }
                            )) {
                                ForEach(availableScenes) { scene in
                                    Text(scene.title).tag(scene.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        SettingsControlRow(title: "Visual style", subtitle: settings.visualStyle.subtitle) {
                            Picker("Visual Style", selection: binding(
                                get: { settings.visualStyle },
                                set: { current, newValue in
                                    current.visualStyle = newValue
                                }
                            )) {
                                ForEach(VideoCallVisualStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .surfaceCard()

                    VStack(alignment: .leading, spacing: 16) {
                        AppSectionHeader(
                            eyebrow: "Voice",
                            title: "Language and accent",
                            subtitle: "Keep conversation language, explanation language, and reference accent together."
                        )

                        SettingsControlRow(title: "Conversation language", subtitle: "Primary language for the live call.") {
                            Picker("Conversation Language", selection: binding(
                                get: { settings.conversationLanguageID },
                                set: { current, newValue in
                                    current.conversationLanguageID = newValue
                                    current.selectedVoiceBundleID = VoiceCatalog.defaultBundle(
                                        for: current.selectedCharacterID,
                                        languageID: newValue
                                    ).id
                                }
                            )) {
                                ForEach(LanguageCatalog.all) { profile in
                                    Text(profile.displayName).tag(profile.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        SettingsControlRow(title: "Explanation language", subtitle: "Used for hints, feedback, and tutor explanations.") {
                            Picker("Explanation Language", selection: binding(
                                get: { settings.explanationLanguageID },
                                set: { current, newValue in
                                    current.explanationLanguageID = newValue
                                }
                            )) {
                                ForEach(LanguageCatalog.all) { profile in
                                    Text(profile.displayName).tag(profile.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        SettingsControlRow(title: "Voice / accent", subtitle: selectedVoiceBundle.styleDescription) {
                            Picker("Voice / Accent", selection: binding(
                                get: { settings.selectedVoiceBundleID },
                                set: { current, newValue in
                                    current.selectedVoiceBundleID = newValue
                                }
                            )) {
                                ForEach(availableVoiceBundles) { voiceBundle in
                                    Text(voiceBundle.displayName).tag(voiceBundle.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    .surfaceCard()

                    VStack(alignment: .leading, spacing: 16) {
                        AppSectionHeader(
                            eyebrow: "Diagnostics",
                            title: "Compatibility and runtime details",
                            subtitle: "Performance, bundled runtime status, and release validation stay here instead of taking over the main settings path."
                        )

                        DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                            VStack(alignment: .leading, spacing: 16) {
                                SettingsControlRow(title: "Performance tier", subtitle: settings.performanceTier.subtitle) {
                                    Picker("Performance Tier", selection: binding(
                                        get: { settings.performanceTier },
                                        set: { current, newValue in
                                            current.performanceTier = newValue
                                        }
                                    )) {
                                        ForEach(PerformanceTier.allCases) { tier in
                                            Text(tier.title).tag(tier)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                SettingsControlRow(title: "Backend", subtitle: "Current preference for local inference execution.") {
                                    Picker("Backend", selection: binding(
                                        get: { settings.backendPreference },
                                        set: { current, newValue in
                                            current.backendPreference = newValue
                                        }
                                    )) {
                                        ForEach(InferenceBackendPreference.allCases) { preference in
                                            Text(preference.title).tag(preference)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Speech rate")
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .foregroundStyle(AppTheme.ink)
                                        Spacer()
                                        Text(String(format: "%.2f", draftSpeechRate))
                                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                                            .foregroundStyle(AppTheme.mutedInk)
                                    }

                                    Slider(
                                        value: $draftSpeechRate,
                                        in: 0.35...0.62,
                                        onEditingChanged: { editing in
                                            isEditingSpeechRate = editing
                                            guard editing == false else { return }
                                            let committedValue = draftSpeechRate
                                            Task {
                                                try? await rootState.updateCompanionSettings { current in
                                                    current.speechRate = Float(committedValue)
                                                }
                                            }
                                        }
                                    )
                                    .tint(AppTheme.warmAccent)
                                }
                                .surfaceCard(padding: 16, fill: AppTheme.canvasLift, shadowOpacity: 0.03)

                                DiagnosticsInfoCard(
                                    title: "Bundled portrait",
                                    rows: [
                                        ("Photo character", CharacterCatalog.primaryPortraitAvailable ? "Active" : "Missing asset"),
                                        ("Model", modelManager.selectedModel.displayName),
                                        ("Availability", modelManager.selectedRecord.isReadyForInference ? "Ready offline" : "Needs attention"),
                                        ("Validated", modelManager.selectedRecord.integrityCheckPassed ? "Yes" : "No")
                                    ]
                                )

                                DiagnosticsInfoCard(
                                    title: "Speech runtime",
                                    rows: [
                                        ("ASR", speechRuntimeSummary(for: speechRuntimeStatus.asr)),
                                        ("TTS", speechRuntimeSummary(for: speechRuntimeStatus.tts))
                                    ],
                                    footnotes: [
                                        speechRuntimeStatus.asr.fallbackReason,
                                        speechRuntimeStatus.tts.fallbackReason
                                    ]
                                )

                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Release validation budgets")
                                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                                        .foregroundStyle(AppTheme.ink)

                                    ForEach(ReleaseValidationSpec.current.budgets) { budget in
                                        HStack {
                                            Text(budget.title)
                                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                                .foregroundStyle(AppTheme.ink)
                                            Spacer()
                                            Text("\(budget.budgetMilliseconds) ms")
                                                .font(.system(.footnote, design: .rounded, weight: .bold))
                                                .foregroundStyle(AppTheme.mutedInk)
                                        }
                                    }

                                    Divider()

                                    ForEach(ReleaseValidationSpec.current.blockingConditions, id: \.self) { condition in
                                        Label(condition, systemImage: "exclamationmark.circle")
                                            .font(.system(.footnote, design: .rounded))
                                            .foregroundStyle(AppTheme.mutedInk)
                                    }
                                }
                                .surfaceCard(padding: 16, fill: AppTheme.canvasLift, shadowOpacity: 0.03)
                            }
                            .padding(.top, 16)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Show diagnostics")
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                        .foregroundStyle(AppTheme.ink)
                                    Text("Expand for performance, runtime, and validation details.")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(AppTheme.mutedInk)
                                }
                                Spacer()
                                Image(systemName: diagnosticsExpanded ? "chevron.up.circle.fill" : "waveform.path.ecg")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(AppTheme.warmAccent)
                            }
                        }
                    }
                    .surfaceCard(fill: AppTheme.secondarySurface, shadowOpacity: 0.05)

                    VStack(alignment: .leading, spacing: 14) {
                        AppSectionHeader(
                            eyebrow: "Storage",
                            title: "Local reset",
                            subtitle: "Clear saved sessions and memory without leaving the settings flow."
                        )

                        Button(role: .destructive) {
                            Task { await rootState.resetMemory() }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "trash")
                                Text("Reset all local memory")
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color(red: 0.72, green: 0.24, blue: 0.22))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .surfaceCard(fill: AppTheme.secondarySurface, shadowOpacity: 0.05)
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Companion")
        .onAppear {
            draftSpeechRate = Double(settings.speechRate)
        }
        .onChange(of: settings.speechRate) { _, newValue in
            guard isEditingSpeechRate == false else { return }
            draftSpeechRate = Double(newValue)
        }
        .task(id: "\(settings.selectedCharacterID)|\(conversationLanguage.id)|\(settings.selectedVoiceBundleID)") {
            container.prewarmSpeechRuntimeIfNeeded(
                characterID: settings.selectedCharacterID,
                languageID: conversationLanguage.id,
                voiceBundleID: settings.selectedVoiceBundleID
            )
        }
    }

    private func settingsHero(
        selectedCharacter: CharacterProfile,
        selectedScene: CharacterScene,
        visualStyle: VideoCallVisualStyle,
        selectedVoiceBundle: VoiceBundle,
        conversationLanguage: LanguageProfile,
        explanationLanguage: LanguageProfile
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            CharacterStageSurface(
                character: selectedCharacter,
                scene: selectedScene,
                visualStyle: visualStyle,
                emphasis: .preview,
                surfaceKind: .settingsPreview,
                size: CGSize(width: 112, height: 136),
                isAnimated: false,
                showsBackdrop: false,
                groundShadowWidth: 78,
                groundShadowHeight: 12,
                groundShadowBlur: 8
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(selectedCharacter.displayName)
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(AppTheme.ink)
                Text(selectedCharacter.heroHeadline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    AppCapsuleBadge(text: selectedScene.title, tint: AppTheme.coolAccent, foreground: AppTheme.ink, backgroundOpacity: 0.14)
                    AppCapsuleBadge(text: selectedVoiceBundle.accentLabel, tint: AppTheme.warmAccent, foreground: AppTheme.ink, backgroundOpacity: 0.18)
                }

                Text("Conversation in \(conversationLanguage.displayName), explanations in \(explanationLanguage.displayName).")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
        .surfaceCard(fill: AppTheme.secondarySurface, shadowOpacity: 0.05)
    }

    private func binding<Value: Equatable & Sendable>(
        get: @escaping @Sendable () -> Value,
        set: @escaping @Sendable (inout CompanionSettings, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: get,
            set: { newValue in
                Task {
                    try? await rootState.updateCompanionSettings { current in
                        set(&current, newValue)
                    }
                }
            }
        )
    }

    private func speechRuntimeSummary(for descriptor: SpeechRuntimeDescriptor) -> String {
        let availability: String
        switch descriptor.assetAvailability {
        case .bundledReady:
            availability = "Bundled asset ready"
        case .bundledMissing:
            availability = "Bundled asset missing"
        case .fallbackOnly:
            availability = "Fallback only"
        }

        return "\(descriptor.activeRuntimeID) • \(availability)"
    }
}

private struct SettingsControlRow<Control: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                control()
                    .labelsHidden()
                    .tint(AppTheme.warmAccent)
            }

            Divider()
                .opacity(0.35)
        }
    }
}

private struct DiagnosticsInfoCard: View {
    let title: String
    let rows: [(String, String)]
    var footnotes: [String?] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(row.1)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(AppTheme.mutedInk)
                        .multilineTextAlignment(.trailing)
                }
            }

            ForEach(Array(footnotes.compactMap { $0 }.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .surfaceCard(padding: 16, fill: AppTheme.canvasLift, shadowOpacity: 0.03)
    }
}
