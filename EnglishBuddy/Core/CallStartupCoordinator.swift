import Foundation

enum CallStartupFailureKind: Equatable {
    case permissions
    case speechUnsupported
    case runtimePackaging
    case modelIntegrity
    case inferenceStalled
    case audioSessionFailure
}

struct PreparedCallLaunch {
    var mode: ConversationMode
    var session: ConversationSession
    var inputMode: CallInputMode
    var openingInstruction: String
    var voiceBundle: VoiceBundle
    var voiceStyle: VoiceStyle
    var speechChunkingPolicy: SpeechChunkingPolicy
    var conversationPreface: ConversationPreface = ConversationPreface(systemPrompt: "", starterMessages: [])
    var memoryContext: String = ""
    var inferenceBackend: InferenceBackendPreference = .gpu
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
    private let performanceGovernor: PerformanceGovernor
    private(set) var lastReadinessSnapshot: CallReadinessSnapshot?

    init(
        inferenceEngine: InferenceEngineProtocol,
        speechPipeline: SpeechPipelineProtocol,
        memoryStore: FileMemoryStore,
        promptComposer: PromptComposer,
        modelManager: ModelDownloadManager,
        performanceGovernor: PerformanceGovernor? = nil
    ) {
        self.inferenceEngine = inferenceEngine
        self.speechPipeline = speechPipeline
        self.memoryStore = memoryStore
        self.promptComposer = promptComposer
        self.modelManager = modelManager
        self.performanceGovernor = performanceGovernor ?? PerformanceGovernor()
    }

    func prepareCall(
        mode: ConversationMode,
        preferredScenarioID: String? = nil,
        continuationAnchor: ConversationSession? = nil
    ) async -> CallStartupResult {
        StartupTrace.mark("CallStartupCoordinator.prepareCall.begin mode=\(mode.rawValue)")
        do {
            lastReadinessSnapshot = nil
            await modelManager.repairCorruptionIfNeeded()
            StartupTrace.mark("CallStartupCoordinator.prepareCall.afterRepairCorruption")

            let snapshot = await memoryStore.fetchSnapshot()
            StartupTrace.mark("CallStartupCoordinator.prepareCall.fetchedSnapshot")
            let character = CharacterCatalog.profile(for: snapshot.companionSettings.selectedCharacterID)
            let characterBundle = CharacterCatalog.bundle(for: character.id)
            let scene = CharacterCatalog.scene(
                for: snapshot.companionSettings.selectedSceneID,
                characterID: character.id
            )
            let conversationLanguage = LanguageCatalog.profile(for: snapshot.companionSettings.conversationLanguageID)
            let explanationLanguage = LanguageCatalog.profile(for: snapshot.companionSettings.explanationLanguageID)
            let voiceBundle = VoiceCatalog.bundle(
                for: snapshot.companionSettings.selectedVoiceBundleID,
                characterID: character.id,
                languageID: conversationLanguage.id
            )
            let requestedBackend = snapshot.companionSettings.backendPreference
            performanceGovernor.apply(settings: snapshot.companionSettings)
            #if targetEnvironment(simulator)
            let effectiveBackend = requestedBackend
            #else
            // Physical devices currently prioritize stable offline calls over GPU throughput.
            let effectiveBackend: InferenceBackendPreference = requestedBackend == .gpu ? .cpu : requestedBackend
            #endif
            let speechRuntimeStatus = speechPipeline.runtimeStatus(
                conversationLanguage: conversationLanguage,
                voiceBundle: voiceBundle
            )
            StartupTrace.mark("CallStartupCoordinator.prepareCall.runtimeStatus asr=\(speechRuntimeStatus.asr.activeRuntimeID) tts=\(speechRuntimeStatus.tts.activeRuntimeID)")
            let runtimeBuildFacts = SpeechRuntimeBuildFacts.resolve(
                from: Bundle.main.resourceURL?.appendingPathComponent("SpeechAssets", isDirectory: true)
            )

            if runtimeBuildFacts.strictReleaseLane && speechRuntimeStatus.usesFallbackRuntime {
                let message = "This build requires bundled local speech runtimes, but the current package still falls back to system speech services."
                lastReadinessSnapshot = makeReadinessSnapshot(
                    disposition: .fatal,
                    inputMode: nil,
                    capabilityStatus: .temporarilyUnavailable,
                    modelReady: modelManager.selectedRecord.isReadyForInference,
                    modelStatusMessage: "\(modelManager.selectedModel.displayName) is ready.",
                    runtimeStatus: speechRuntimeStatus,
                    conversationLanguageID: conversationLanguage.id,
                    voiceBundleID: voiceBundle.id,
                    requestedBackend: requestedBackend,
                    effectiveBackend: effectiveBackend,
                    degradedReason: message
                )
                return .fatalConfigurationFailure(message: message)
            }

            guard modelManager.selectedRecord.isReadyForInference else {
                let message: String
                if case let .unavailable(details) = modelManager.activeModelReadiness {
                    message = details
                } else {
                    message = "\(modelManager.selectedModel.displayName) is not ready for offline calls."
                }
                lastReadinessSnapshot = makeReadinessSnapshot(
                    disposition: .fatal,
                    inputMode: nil,
                    capabilityStatus: conversationLanguage.supportsSpeechConversation ? .temporarilyUnavailable : .onDeviceUnsupported,
                    modelReady: false,
                    modelStatusMessage: message,
                    runtimeStatus: speechRuntimeStatus,
                    conversationLanguageID: conversationLanguage.id,
                    voiceBundleID: voiceBundle.id,
                    requestedBackend: requestedBackend,
                    effectiveBackend: effectiveBackend,
                    degradedReason: message
                )
                return .fatalConfigurationFailure(message: message)
            }
            let memoryContext = performanceGovernor.clampedMemoryContext(
                await memoryStore.fetchLearningContext()
            )
            StartupTrace.mark("CallStartupCoordinator.prepareCall.memoryContext.ready")

            speechPipeline.configureASR(localeIdentifier: conversationLanguage.asrLocale)
            speechPipeline.configureTTS(voiceBundle: voiceBundle)
            StartupTrace.mark("CallStartupCoordinator.prepareCall.speechConfigured")

            let inputMode: CallInputMode
            let capability: SpeechCapabilityStatus
            var degradedReason: String?
            if conversationLanguage.supportsSpeechConversation == false {
                capability = .onDeviceUnsupported
                inputMode = .textAssisted
                degradedReason = "\(conversationLanguage.displayName) is text-assisted in this release."
            } else {
                #if targetEnvironment(simulator)
                capability = await speechPipeline.evaluateSpeechCapability(requestPermissions: false)
                StartupTrace.mark("CallStartupCoordinator.prepareCall.capability=\(String(describing: capability))")
                switch capability {
                case .ready:
                    inputMode = .liveVoice
                case .permissionsRequired, .permissionsDenied, .onDeviceUnsupported, .temporarilyUnavailable:
                    inputMode = .textAssisted
                    degradedReason = "Live voice is unavailable right now, so the call is starting in typed fallback mode."
                }
                #else
                capability = await speechPipeline.evaluateSpeechCapability(requestPermissions: true)
                switch capability {
                case .ready:
                    inputMode = .liveVoice
                case .permissionsRequired, .permissionsDenied:
                    let message = "EnglishBuddy needs microphone and speech recognition access before the \(conversationLanguage.displayName.lowercased()) call can begin."
                    lastReadinessSnapshot = makeReadinessSnapshot(
                        disposition: .fatal,
                        inputMode: nil,
                        capabilityStatus: capability,
                        modelReady: true,
                        modelStatusMessage: "\(modelManager.selectedModel.displayName) is ready.",
                        runtimeStatus: speechRuntimeStatus,
                        conversationLanguageID: conversationLanguage.id,
                        voiceBundleID: voiceBundle.id,
                        requestedBackend: requestedBackend,
                        effectiveBackend: effectiveBackend,
                        degradedReason: message
                    )
                    return .recoverableFailure(
                        kind: .permissions,
                        message: message,
                        suggestedAction: "Allow the permissions, then try the call again."
                    )
                case .onDeviceUnsupported:
                    let message = "This device cannot run on-device \(conversationLanguage.displayName.lowercased()) speech recognition for live calls."
                    lastReadinessSnapshot = makeReadinessSnapshot(
                        disposition: .fatal,
                        inputMode: nil,
                        capabilityStatus: capability,
                        modelReady: true,
                        modelStatusMessage: "\(modelManager.selectedModel.displayName) is ready.",
                        runtimeStatus: speechRuntimeStatus,
                        conversationLanguageID: conversationLanguage.id,
                        voiceBundleID: voiceBundle.id,
                        requestedBackend: requestedBackend,
                        effectiveBackend: effectiveBackend,
                        degradedReason: message
                    )
                    return .recoverableFailure(
                        kind: .speechUnsupported,
                        message: message,
                        suggestedAction: "Use a supported iPhone or install the required on-device language resources."
                    )
                case .temporarilyUnavailable:
                    let message = "\(conversationLanguage.displayName) speech recognition is temporarily unavailable right now."
                    lastReadinessSnapshot = makeReadinessSnapshot(
                        disposition: .fatal,
                        inputMode: nil,
                        capabilityStatus: capability,
                        modelReady: true,
                        modelStatusMessage: "\(modelManager.selectedModel.displayName) is ready.",
                        runtimeStatus: speechRuntimeStatus,
                        conversationLanguageID: conversationLanguage.id,
                        voiceBundleID: voiceBundle.id,
                        requestedBackend: requestedBackend,
                        effectiveBackend: effectiveBackend,
                        degradedReason: message
                    )
                    return .recoverableFailure(
                        kind: .audioSessionFailure,
                        message: message,
                        suggestedAction: "Close other audio apps and try the call again."
                    )
                }
                #endif
            }

            lastReadinessSnapshot = makeReadinessSnapshot(
                disposition: inputMode == .liveVoice ? .liveVoice : .textAssisted,
                inputMode: inputMode,
                capabilityStatus: capability,
                modelReady: true,
                modelStatusMessage: "\(modelManager.selectedModel.displayName) is ready.",
                runtimeStatus: speechRuntimeStatus,
                conversationLanguageID: conversationLanguage.id,
                voiceBundleID: voiceBundle.id,
                requestedBackend: requestedBackend,
                effectiveBackend: effectiveBackend,
                degradedReason: degradedReason
            )

            let scenario = preferredScenarioID
                .flatMap { ScenarioCatalog.preset(for: $0, mode: mode) }
                ?? ScenarioCatalog.recommended(for: snapshot.learnerProfile, mode: mode)
            let learningPlan: LearningFocusPlan
            if let continuationAnchor {
                learningPlan = LearningFocusPlan.continued(
                    learner: snapshot.learnerProfile,
                    scenario: scenario,
                    mode: mode,
                    vocabulary: snapshot.vocabulary,
                    previousSession: continuationAnchor
                )
            } else {
                learningPlan = LearningFocusPlan.suggested(
                    learner: snapshot.learnerProfile,
                    scenario: scenario,
                    mode: mode,
                    vocabulary: snapshot.vocabulary
                )
            }
            let preface = promptComposer.makePreface(
                learner: snapshot.learnerProfile,
                characterBundle: characterBundle,
                scene: scene,
                settings: snapshot.companionSettings,
                memoryContext: memoryContext,
                mode: mode,
                scenario: scenario,
                learningPlan: learningPlan,
                conversationLanguage: conversationLanguage,
                explanationLanguage: explanationLanguage,
                voiceBundle: voiceBundle,
                continuation: continuationAnchor
            )
            let openingInstruction = promptComposer.makeOpeningInstruction(
                learner: snapshot.learnerProfile,
                characterBundle: characterBundle,
                mode: mode,
                scenario: scenario,
                learningPlan: learningPlan,
                conversationLanguage: conversationLanguage,
                explanationLanguage: explanationLanguage,
                continuation: continuationAnchor
            )
            StartupTrace.mark("CallStartupCoordinator.prepareCall.promptReady")

            let continuationThreadID = continuationAnchor?.continuationThreadID
                ?? continuationAnchor?.id.uuidString
                ?? UUID().uuidString
            let performanceSnapshot = PerformanceSnapshot(
                tier: snapshot.companionSettings.performanceTier,
                backendPreference: effectiveBackend,
                lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                speechRuntimeStatus: speechRuntimeStatus
            )

            let session = ConversationSession(
                mode: mode,
                characterID: character.id,
                characterBundleID: characterBundle.id,
                voiceBundleID: voiceBundle.id,
                voiceAccent: voiceBundle.accent,
                sceneID: scene.id,
                scenarioID: scenario.id,
                scenarioCategory: scenario.category,
                languageProfileID: conversationLanguage.id,
                continuationThreadID: continuationThreadID,
                performanceSnapshot: performanceSnapshot,
                runtimeSelection: lastReadinessSnapshot?.runtimeSelection,
                learningPlanSnapshot: learningPlan
            )
            try await memoryStore.upsertSession(session)
            StartupTrace.mark("CallStartupCoordinator.prepareCall.ready session=\(session.id.uuidString)")
            return .ready(
                PreparedCallLaunch(
                    mode: mode,
                    session: session,
                    inputMode: inputMode,
                    openingInstruction: openingInstruction,
                    voiceBundle: voiceBundle,
                    voiceStyle: VoiceStyle(
                        rate: max(0.35, min(snapshot.companionSettings.speechRate * voiceBundle.rateMultiplier * (mode == .tutor ? 0.94 : 1.0), 0.62)),
                        pitchMultiplier: voiceBundle.pitchMultiplier * (mode == .chat ? 1.0 : 0.98),
                        languageCode: voiceBundle.languageCode,
                        voiceIdentifier: snapshot.companionSettings.preferredVoiceIdentifier ?? voiceBundle.voiceIdentifier,
                        prosodyPolicy: prosodyPolicy(for: voiceBundle, mode: mode),
                        accent: voiceBundle.accent
                    ),
                    speechChunkingPolicy: mode == .tutor ? .sentence : voiceBundle.chunkingPolicy,
                    conversationPreface: preface,
                    memoryContext: memoryContext,
                    inferenceBackend: effectiveBackend
                )
            )
        } catch {
            StartupTrace.mark("CallStartupCoordinator.prepareCall.error domain=\((error as NSError).domain) code=\((error as NSError).code) message=\(error.localizedDescription)")
            speechPipeline.stopListening()
            speechPipeline.interruptSpeech(reason: .runtimeReset)
            inferenceEngine.cancelCurrentResponse()
            return classify(error)
        }
    }

    private func prosodyPolicy(for voiceBundle: VoiceBundle, mode: ConversationMode) -> SpeechProsodyPolicy {
        if mode == .tutor {
            return voiceBundle.accent == .british ? .tutorClearUK : .tutorClearUS
        }
        return voiceBundle.prosodyPolicy
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

    private func makeReadinessSnapshot(
        disposition: CallReadinessDisposition,
        inputMode: CallInputMode?,
        capabilityStatus: SpeechCapabilityStatus,
        modelReady: Bool,
        modelStatusMessage: String,
        runtimeStatus: SpeechRuntimeStatusSnapshot,
        conversationLanguageID: String,
        voiceBundleID: String,
        requestedBackend: InferenceBackendPreference,
        effectiveBackend: InferenceBackendPreference,
        degradedReason: String?
    ) -> CallReadinessSnapshot {
        CallReadinessSnapshot(
            disposition: disposition,
            inputMode: inputMode,
            capabilityStatus: capabilityStatus,
            modelReady: modelReady,
            modelStatusMessage: modelStatusMessage,
            runtimeSelection: SpeechRuntimeSelectionSnapshot(
                conversationLanguageID: conversationLanguageID,
                voiceBundleID: voiceBundleID,
                runtimeStatus: runtimeStatus
            ),
            requestedBackend: requestedBackend,
            effectiveBackend: effectiveBackend,
            degradedReason: degradedReason,
            evaluatedAt: .now
        )
    }
}
