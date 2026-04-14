import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        let snapshot = container.rootState.snapshot
        let settings = snapshot.companionSettings
        let selectedCharacter = CharacterCatalog.profile(for: settings.selectedCharacterID)
        let availableScenes = CharacterCatalog.availableScenes(for: selectedCharacter.id)

        return ZStack {
            AppCanvasBackground()

            List {
                Section("Companion") {
                    Picker("Character", selection: Binding(
                        get: { settings.selectedCharacterID },
                        set: { newValue in
                            Task {
                                try? await container.memoryStore.updateCompanionSettings { current in
                                    current.selectedCharacterID = newValue
                                    current.selectedSceneID = CharacterCatalog.defaultScene(for: newValue).id
                                }
                                await container.rootState.refresh()
                            }
                        }
                    )) {
                        ForEach(CharacterCatalog.profiles) { profile in
                            Text(profile.displayName).tag(profile.id)
                        }
                    }

                    Picker("Scene", selection: Binding(
                        get: { settings.selectedSceneID },
                        set: { newValue in
                            Task {
                                try? await container.memoryStore.updateCompanionSettings { current in
                                    current.selectedSceneID = newValue
                                }
                                await container.rootState.refresh()
                            }
                        }
                    )) {
                        ForEach(availableScenes) { scene in
                            Text(scene.title).tag(scene.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedCharacter.displayName)
                            .font(.system(.headline, design: .rounded))
                        Text(selectedCharacter.roleDescription)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Call Behavior") {
                    Toggle("Chinese explanations", isOn: Binding(
                        get: { settings.allowChineseHints },
                        set: { newValue in
                            Task {
                                try? await container.memoryStore.updateCompanionSettings { current in
                                    current.allowChineseHints = newValue
                                }
                                await container.rootState.refresh()
                            }
                        }
                    ))

                    Picker("Backend", selection: Binding(
                        get: { settings.backendPreference },
                        set: { newValue in
                            Task {
                                try? await container.memoryStore.updateCompanionSettings { current in
                                    current.backendPreference = newValue
                                }
                                await container.rootState.refresh()
                            }
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
                            Text(String(format: "%.2f", settings.speechRate))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.speechRate) },
                                set: { newValue in
                                    Task {
                                        try? await container.memoryStore.updateCompanionSettings { current in
                                            current.speechRate = Float(newValue)
                                        }
                                        await container.rootState.refresh()
                                    }
                                }
                            ),
                            in: 0.35...0.62
                        )
                    }
                }

                Section("Offline Runtime") {
                    LabeledContent("Current Model", value: container.modelManager.selectedModel.displayName)
                    LabeledContent(
                        "Availability",
                        value: container.modelManager.selectedRecord.isReadyForInference ? "Ready offline" : "Needs attention"
                    )
                    LabeledContent(
                        "Validated",
                        value: container.modelManager.selectedRecord.integrityCheckPassed ? "Yes" : "No"
                    )
                    Text("EnglishBuddy keeps the model on-device and remembers your selected character, scene, and learning context locally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Storage") {
                    Button("Reset all local memory", role: .destructive) {
                        Task { await container.rootState.resetMemory() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
    }
}
