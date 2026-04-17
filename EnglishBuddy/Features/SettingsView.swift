import SwiftUI

struct SettingsView: View {
    let container: AppContainer
    @ObservedObject private var rootState: RootViewModel
    @ObservedObject private var modelManager: ModelDownloadManager
    @State private var draftSpeechRate = Double(CompanionSettings.default.speechRate)
    @State private var isEditingSpeechRate = false

    init(container: AppContainer) {
        self.container = container
        _rootState = ObservedObject(wrappedValue: container.rootState)
        _modelManager = ObservedObject(wrappedValue: container.modelManager)
    }

    var body: some View {
        let snapshot = rootState.snapshot
        let settings = snapshot.companionSettings
        let selectedCharacter = CharacterCatalog.profile(for: settings.selectedCharacterID)
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
            AppCanvasBackground()

            List {
                Section("Character Bundle") {
                    HStack(alignment: .center, spacing: 16) {
                        CharacterStageSurface(
                            character: selectedCharacter,
                            scene: CharacterCatalog.scene(for: settings.selectedSceneID, characterID: selectedCharacter.id),
                            visualStyle: settings.visualStyle,
                            emphasis: .preview,
                            surfaceKind: .settingsPreview,
                            size: CGSize(width: 104, height: 128),
                            isAnimated: false,
                            showsBackdrop: false,
                            groundShadowWidth: 72,
                            groundShadowHeight: 12,
                            groundShadowBlur: 8
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedCharacter.displayName)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Text(CharacterCatalog.scene(for: settings.selectedSceneID, characterID: selectedCharacter.id).title)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(settings.visualStyle.title)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

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

                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedCharacter.displayName)
                            .font(.system(.headline, design: .rounded))
                        Text(selectedCharacter.roleDescription)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(selectedCharacter.heroHeadline)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Language & Voice") {
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Conversation: \(conversationLanguage.displayName)")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text("Explanation: \(explanationLanguage.displayName)")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("Reference Accent: \(selectedVoiceBundle.accentLabel)")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                        Text(selectedVoiceBundle.styleDescription)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Advanced") {
                    DisclosureGroup("Diagnostics & Compatibility") {
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

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Speech Rate")
                                Spacer()
                                Text(String(format: "%.2f", draftSpeechRate))
                                    .foregroundStyle(.secondary)
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
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(
                                "Photo Character",
                                value: CharacterCatalog.primaryPortraitAvailable ? "Active" : "Missing Asset"
                            )
                            Text(
                                CharacterCatalog.primaryPortraitAvailable
                                    ? "The bundled portrait is the default release character path. This compatibility flag stays synchronized automatically."
                                    : "No bundled portrait asset is available, so the app will fall back to non-photo development visuals."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("On-device engine")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            LabeledContent("Current Model", value: modelManager.selectedModel.displayName)
                            LabeledContent(
                                "Availability",
                                value: modelManager.selectedRecord.isReadyForInference ? "Ready offline" : "Needs attention"
                            )
                            LabeledContent(
                                "Validated",
                                value: modelManager.selectedRecord.integrityCheckPassed ? "Yes" : "No"
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Speech runtime")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            LabeledContent("ASR", value: speechRuntimeSummary(for: speechRuntimeStatus.asr))
                            if let fallbackReason = speechRuntimeStatus.asr.fallbackReason {
                                Text(fallbackReason)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            LabeledContent("TTS", value: speechRuntimeSummary(for: speechRuntimeStatus.tts))
                            if let fallbackReason = speechRuntimeStatus.tts.fallbackReason {
                                Text(fallbackReason)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        DisclosureGroup("Debug Validation Spec") {
                            ForEach(ReleaseValidationSpec.current.budgets) { budget in
                                LabeledContent(budget.title, value: "\(budget.budgetMilliseconds) ms")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Blocking conditions")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                ForEach(ReleaseValidationSpec.current.blockingConditions, id: \.self) { condition in
                                    Label(condition, systemImage: "exclamationmark.circle")
                                        .font(.system(.footnote, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Text("Runtime diagnostics and compatibility details stay here so the main settings path stays focused on character, scene, language, and voice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Storage") {
                    Button("Reset all local memory", role: .destructive) {
                        Task { await rootState.resetMemory() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
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
