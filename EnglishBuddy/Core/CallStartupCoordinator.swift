import Foundation

enum CallStartupFailureKind: Equatable {
    case permissions
    case speechUnsupported
    case runtimePackaging
    case modelIntegrity
    case inferenceStalled
    case audioSessionFailure
}

enum SpeechCapabilityStatus: Equatable {
    case ready
    case permissionsRequired
    case permissionsDenied
    case onDeviceUnsupported
    case temporarilyUnavailable
}

enum CallInputMode: String, Codable, Equatable {
    case liveVoice
    case textAssisted
}

struct PreparedCallLaunch {
    var mode: ConversationMode
    var session: ConversationSession
    var inputMode: CallInputMode
    var openingInstruction: String
    var voiceStyle: VoiceStyle
}

enum CallStartupResult {
    case ready(PreparedCallLaunch)
    case recoverableFailure(kind: CallStartupFailureKind, message: String, suggestedAction: String)
    case fatalConfigurationFailure(message: String)
}

enum CallStartupState: Equatable {
    case idle
    case starting(String)
    case recoverableFailure(kind: CallStartupFailureKind, message: String, suggestedAction: String)
}

@MainActor
final class CallStartupCoordinator {
    private let inferenceEngine: InferenceEngineProtocol
    private let speechPipeline: SpeechPipelineProtocol
    private let memoryStore: FileMemoryStore
    private let promptComposer: PromptComposer
    private let modelManager: ModelDownloadManager

    init(
        inferenceEngine: InferenceEngineProtocol,
        speechPipeline: SpeechPipelineProtocol,
        memoryStore: FileMemoryStore,
        promptComposer: PromptComposer,
        modelManager: ModelDownloadManager
    ) {
        self.inferenceEngine = inferenceEngine
        self.speechPipeline = speechPipeline
        self.memoryStore = memoryStore
        self.promptComposer = promptComposer
        self.modelManager = modelManager
    }

    func prepareCall(mode: ConversationMode) async -> CallStartupResult {
        do {
            await modelManager.repairCorruptionIfNeeded()

            guard modelManager.selectedRecord.isReadyForInference else {
                let message: String
                if case let .unavailable(details) = modelManager.activeModelReadiness {
                    message = details
                } else {
                    message = "\(modelManager.selectedModel.displayName) is not ready for offline calls."
                }
                return .fatalConfigurationFailure(message: message)
            }

            let inputMode: CallInputMode
            #if targetEnvironment(simulator)
            let capability = await speechPipeline.evaluateSpeechCapability(requestPermissions: false)
            switch capability {
            case .ready:
                inputMode = .liveVoice
            case .permissionsRequired, .permissionsDenied, .onDeviceUnsupported, .temporarilyUnavailable:
                inputMode = .textAssisted
            }
            #else
            let capability = await speechPipeline.evaluateSpeechCapability(requestPermissions: true)
            switch capability {
            case .ready:
                inputMode = .liveVoice
            case .permissionsRequired, .permissionsDenied:
                return .recoverableFailure(
                    kind: .permissions,
                    message: "EnglishBuddy needs microphone and speech recognition access before the call can begin.",
                    suggestedAction: "Allow the permissions, then try the call again."
                )
            case .onDeviceUnsupported:
                return .recoverableFailure(
                    kind: .speechUnsupported,
                    message: "This device cannot run on-device English speech recognition for live calls.",
                    suggestedAction: "Use a supported iPhone or update the device language resources."
                )
            case .temporarilyUnavailable:
                return .recoverableFailure(
                    kind: .audioSessionFailure,
                    message: "English speech recognition is temporarily unavailable right now.",
                    suggestedAction: "Close other audio apps and try the call again."
                )
            }
            #endif

            let snapshot = await memoryStore.fetchSnapshot()
            let memoryContext = await memoryStore.fetchLearningContext()
            let character = CharacterCatalog.profile(for: snapshot.companionSettings.selectedCharacterID)
            let scene = CharacterCatalog.scene(
                for: snapshot.companionSettings.selectedSceneID,
                characterID: character.id
            )
            let scenario = ScenarioCatalog.recommended(for: snapshot.learnerProfile, mode: mode)
            let learningPlan = LearningFocusPlan.suggested(
                learner: snapshot.learnerProfile,
                scenario: scenario,
                mode: mode,
                vocabulary: snapshot.vocabulary
            )
            let preface = promptComposer.makePreface(
                learner: snapshot.learnerProfile,
                character: character,
                scene: scene,
                settings: snapshot.companionSettings,
                memoryContext: memoryContext,
                mode: mode,
                scenario: scenario,
                learningPlan: learningPlan
            )
            let openingInstruction = promptComposer.makeOpeningInstruction(
                learner: snapshot.learnerProfile,
                character: character,
                mode: mode,
                scenario: scenario,
                learningPlan: learningPlan
            )

            try await inferenceEngine.prepare(modelURL: modelManager.modelURL, backend: snapshot.companionSettings.backendPreference)
            try await inferenceEngine.startConversation(preface: preface, memoryContext: memoryContext, mode: mode)

            if inputMode == .liveVoice {
                try await speechPipeline.startListening()
            }

            await modelManager.markModelUsed()

            let session = ConversationSession(
                mode: mode,
                characterID: character.id,
                sceneID: scene.id,
                scenarioID: scenario.id,
                learningPlanSnapshot: learningPlan
            )
            try await memoryStore.upsertSession(session)
            return .ready(
                PreparedCallLaunch(
                    mode: mode,
                    session: session,
                    inputMode: inputMode,
                    openingInstruction: openingInstruction,
                    voiceStyle: VoiceStyle(
                        rate: snapshot.companionSettings.speechRate,
                        pitchMultiplier: mode == .chat ? 1.04 : 1.0,
                        languageCode: "en-US"
                    )
                )
            )
        } catch {
            speechPipeline.stopListening()
            speechPipeline.interruptSpeech()
            inferenceEngine.cancelCurrentResponse()
            return classify(error)
        }
    }

    private func classify(_ error: Error) -> CallStartupResult {
        let nsError = error as NSError
        let message = error.localizedDescription

        if nsError.domain == "SpeechPipeline" {
            switch nsError.code {
            case 1, 2:
                return .recoverableFailure(
                    kind: .permissions,
                    message: message,
                    suggestedAction: "Enable microphone and speech recognition access in Settings, then try again."
                )
            case 3, 5:
                #if targetEnvironment(simulator)
                return .recoverableFailure(
                    kind: .speechUnsupported,
                    message: "Live voice input is unavailable in the simulator. The call can still run with typed input once the engine is ready.",
                    suggestedAction: "Retry in the simulator or switch to a real iPhone for live voice practice."
                )
                #else
                return .recoverableFailure(
                    kind: .speechUnsupported,
                    message: message,
                    suggestedAction: "Use a supported iPhone for live on-device speech practice."
                )
                #endif
            default:
                return .recoverableFailure(
                    kind: .audioSessionFailure,
                    message: message,
                    suggestedAction: "Reset the audio route and start the call again."
                )
            }
        }

        if nsError.domain == "LiteRTBridge" {
            return .recoverableFailure(
                kind: .runtimePackaging,
                message: message,
                suggestedAction: "Restart the call. If it keeps failing, rebuild the app package with the bundled runtime."
            )
        }

        if nsError.domain == "ConversationOrchestrator" || message.localizedCaseInsensitiveContains("model") {
            return .fatalConfigurationFailure(message: message)
        }

        return .recoverableFailure(
            kind: .audioSessionFailure,
            message: message,
            suggestedAction: "Return to the home screen and start the call again."
        )
    }
}
