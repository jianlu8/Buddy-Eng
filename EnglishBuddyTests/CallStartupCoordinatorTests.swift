import XCTest
@testable import EnglishBuddyCore

@MainActor
final class CallStartupCoordinatorTests: XCTestCase {
    func testPrepareCallReturnsReadyWithoutEagerSpeechOrInferenceActivation() async throws {
        let (filesystem, memoryStore) = try makeEmbeddedFixture()
        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        try await memoryStore.load()
        try await modelManager.ensureBundledBaseReady()

        let inference = StartupInferenceEngine()
        let speech = StartupSpeechPipeline()
        speech.capabilityStatus = .ready
        let coordinator = CallStartupCoordinator(
            inferenceEngine: inference,
            speechPipeline: speech,
            memoryStore: memoryStore,
            promptComposer: PromptComposer(),
            modelManager: modelManager
        )

        let result = await coordinator.prepareCall(mode: .chat)

        guard case let .ready(prepared) = result else {
            return XCTFail("Expected ready result, got \(result)")
        }
        XCTAssertEqual(prepared.mode, .chat)
        XCTAssertEqual(prepared.inputMode, .liveVoice)
        XCTAssertEqual(speech.startListeningCount, 0)
        XCTAssertEqual(speech.configuredASRLocaleIdentifier, LanguageCatalog.english.asrLocale)
        XCTAssertEqual(speech.configuredVoiceBundleID, VoiceCatalog.defaultBundle(for: CharacterCatalog.flagship.id, languageID: LanguageCatalog.english.id).id)
        XCTAssertNil(inference.preparedModelURL)
        XCTAssertEqual(prepared.session.characterBundleID, CharacterCatalog.bundle(for: prepared.session.characterID).id)
        XCTAssertEqual(prepared.session.languageProfileID, LanguageCatalog.english.id)
        XCTAssertEqual(prepared.voiceStyle.languageCode, LanguageCatalog.english.ttsLanguageCode)
        XCTAssertEqual(prepared.speechChunkingPolicy, .adaptive)
        XCTAssertEqual(prepared.memoryContext.isEmpty, false)
        XCTAssertEqual(prepared.inferenceBackend, .gpu)
        XCTAssertEqual(prepared.session.runtimeSelection?.voiceBundleID, prepared.session.voiceBundleID)
        XCTAssertEqual(prepared.session.performanceSnapshot.speechRuntimeStatus.asr.activeRuntimeID, "system-asr-fallback")
        XCTAssertEqual(prepared.session.performanceSnapshot.speechRuntimeStatus.tts.activeRuntimeID, "system-tts-fallback")
        XCTAssertEqual(coordinator.lastReadinessSnapshot?.disposition, .liveVoice)
    }

    func testPrepareCallUsesTextAssistedModeWhenSpeechIsUnsupportedInSimulator() async throws {
        let (filesystem, memoryStore) = try makeEmbeddedFixture()
        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        try await memoryStore.load()
        try await modelManager.ensureBundledBaseReady()

        let inference = StartupInferenceEngine()
        let speech = StartupSpeechPipeline()
        speech.capabilityStatus = .onDeviceUnsupported
        let coordinator = CallStartupCoordinator(
            inferenceEngine: inference,
            speechPipeline: speech,
            memoryStore: memoryStore,
            promptComposer: PromptComposer(),
            modelManager: modelManager
        )

        let result = await coordinator.prepareCall(mode: .tutor)

        guard case let .ready(prepared) = result else {
            return XCTFail("Expected simulator text-assisted readiness, got \(result)")
        }
        XCTAssertEqual(prepared.mode, .tutor)
        XCTAssertEqual(prepared.inputMode, .textAssisted)
        XCTAssertEqual(speech.startListeningCount, 0)
        XCTAssertEqual(coordinator.lastReadinessSnapshot?.disposition, .textAssisted)
    }

    func testPrepareCallUsesTextAssistedModeWhenPermissionsAreDeniedInSimulator() async throws {
        let (filesystem, memoryStore) = try makeEmbeddedFixture()
        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        try await memoryStore.load()
        try await modelManager.ensureBundledBaseReady()

        let coordinator = CallStartupCoordinator(
            inferenceEngine: StartupInferenceEngine(),
            speechPipeline: StartupSpeechPipeline(capabilityStatus: .permissionsDenied),
            memoryStore: memoryStore,
            promptComposer: PromptComposer(),
            modelManager: modelManager
        )

        let result = await coordinator.prepareCall(mode: .chat)

        guard case let .ready(prepared) = result else {
            return XCTFail("Expected simulator fallback readiness, got \(result)")
        }
        XCTAssertEqual(prepared.inputMode, .textAssisted)
        XCTAssertEqual(coordinator.lastReadinessSnapshot?.inputMode, .textAssisted)
    }

    func testPrepareCallUsesPreferredScenarioWhenContinuingSession() async throws {
        let (filesystem, memoryStore) = try makeEmbeddedFixture()
        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        try await memoryStore.load()
        try await modelManager.ensureBundledBaseReady()

        let coordinator = CallStartupCoordinator(
            inferenceEngine: StartupInferenceEngine(),
            speechPipeline: StartupSpeechPipeline(capabilityStatus: .permissionsDenied),
            memoryStore: memoryStore,
            promptComposer: PromptComposer(),
            modelManager: modelManager
        )
        let anchor = ConversationSession(
            mode: .chat,
            summary: "Talked about weekend plans and hiking.",
            characterID: CharacterCatalog.flagship.id,
            sceneID: CharacterCatalog.flagship.defaultSceneID,
            scenarioID: "weekend-plans"
        )

        let result = await coordinator.prepareCall(
            mode: .chat,
            preferredScenarioID: anchor.scenarioID,
            continuationAnchor: anchor
        )

        guard case let .ready(prepared) = result else {
            return XCTFail("Expected continued-call readiness, got \(result)")
        }
        XCTAssertEqual(prepared.session.scenarioID, "weekend-plans")
        XCTAssertTrue(prepared.openingInstruction.localizedCaseInsensitiveContains("follow-up"))
    }

    func testPrepareCallCarriesForwardLearningPlanFromContinuationThread() async throws {
        let (filesystem, memoryStore) = try makeEmbeddedFixture()
        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        try await memoryStore.load()
        try await modelManager.ensureBundledBaseReady()

        let coordinator = CallStartupCoordinator(
            inferenceEngine: StartupInferenceEngine(),
            speechPipeline: StartupSpeechPipeline(capabilityStatus: .permissionsDenied),
            memoryStore: memoryStore,
            promptComposer: PromptComposer(),
            modelManager: modelManager
        )
        let anchor = ConversationSession(
            mode: .tutor,
            summary: "Worked on clearer travel requests.",
            feedbackReport: FeedbackReport(
                pronunciationHighlights: ["Repeat 'world' once slowly, then in a full sentence."],
                carryOverVocabulary: ["clarify", "booking"],
                nextMission: "Next time, ask for help with one reason and one polite follow-up.",
                continuationCue: "Resume from the travel desk request and add one clearer detail."
            ),
            scenarioID: "travel-roleplay",
            continuationThreadID: "thread-continue",
            learningPlanSnapshot: LearningFocusPlan(
                title: "Micro-goal for this call",
                mission: "Ask for help with one direct request.",
                checkpoint: "Push for one clearer follow-up.",
                successSignal: "One request, one reason, one example.",
                pronunciationFocus: ["world"],
                carryOverVocabulary: ["clarify"]
            )
        )

        let result = await coordinator.prepareCall(
            mode: .tutor,
            preferredScenarioID: anchor.scenarioID,
            continuationAnchor: anchor
        )

        guard case let .ready(prepared) = result else {
            return XCTFail("Expected continuation readiness, got \(result)")
        }

        XCTAssertEqual(prepared.session.learningPlanSnapshot?.mission, "Next time, ask for help with one reason and one polite follow-up.")
        XCTAssertEqual(prepared.session.learningPlanSnapshot?.checkpoint, "Resume from the travel desk request and add one clearer detail.")
        XCTAssertEqual(prepared.session.learningPlanSnapshot?.carryOverVocabulary, ["clarify", "booking"])
        XCTAssertEqual(prepared.session.learningPlanSnapshot?.pronunciationFocus, ["world"])
    }

    private func makeEmbeddedFixture() throws -> (AppFilesystem, FileMemoryStore) {
        let descriptor = ModelCatalog.current.defaultDescriptor
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let embeddedDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let embeddedModelURL = embeddedDirectoryURL.appendingPathComponent(descriptor.fileName)
        let embeddedMetadataURL = embeddedDirectoryURL.appendingPathComponent("EmbeddedModelMetadata.json")

        try FileManager.default.createDirectory(at: embeddedDirectoryURL, withIntermediateDirectories: true)
        let contents = Data("seed".utf8)
        try contents.write(to: embeddedModelURL)
        let metadata = """
        {
          "modelID": "\(descriptor.id)",
          "fileName": "\(descriptor.fileName)",
          "version": "\(descriptor.version)",
          "expectedFileSizeBytes": \(contents.count),
          "checksum": "embedded-checksum"
        }
        """
        try XCTUnwrap(metadata.data(using: .utf8)).write(to: embeddedMetadataURL)

        let filesystem = AppFilesystem(
            baseURL: baseURL,
            embeddedModelURL: embeddedModelURL,
            embeddedModelMetadataURL: embeddedMetadataURL
        )
        return (filesystem, FileMemoryStore(filesystem: filesystem))
    }
}

private final class StartupInferenceEngine: InferenceEngineProtocol {
    private(set) var preparedModelURL: URL?

    func prepare(modelURL: URL, backend: InferenceBackendPreference) async throws {
        preparedModelURL = modelURL
    }

    func startConversation(preface: ConversationPreface, memoryContext: String, mode: ConversationMode) async throws {}
    func send(text: String) async throws -> String { "" }
    func sendStreaming(text: String, onToken: @escaping @MainActor (String) -> Void) async throws -> String { "" }
    func cancelCurrentResponse() {}
}

private final class StartupSpeechPipeline: SpeechPipelineProtocol {
    var onPartialTranscript: (@MainActor (String) -> Void)?
    var onFinalTranscript: (@MainActor (String) -> Void)?
    var onVoiceActivity: (@MainActor (Double) -> Void)?
    var onVoiceActivityStateChange: (@MainActor (VoiceActivityState) -> Void)?
    var onRuntimeReadinessChange: (@MainActor (SpeechRuntimeReadiness) -> Void)?
    var onSpeechStateChange: (@MainActor (Bool) -> Void)?
    var onSpeechEnvelope: (@MainActor (Double) -> Void)?
    var onLipSyncFrame: (@MainActor (LipSyncFrame) -> Void)?
    var onInterruptionReason: (@MainActor (SpeechInterruptionReason) -> Void)?

    var capabilityStatus: SpeechCapabilityStatus
    private(set) var startListeningCount = 0
    private(set) var configuredASRLocaleIdentifier = "en-US"
    private(set) var configuredVoiceBundleID: String?

    init(capabilityStatus: SpeechCapabilityStatus = .ready) {
        self.capabilityStatus = capabilityStatus
    }

    func prepareAudioSessionForCall() async throws {}
    func recoverAudioAfterInterruption() async throws {}
    func deactivateAudioSession() {}

    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus {
        capabilityStatus
    }

    func runtimeStatus(
        conversationLanguage: LanguageProfile,
        voiceBundle: VoiceBundle
    ) -> SpeechRuntimeStatusSnapshot {
        SpeechRuntimeStatusSnapshot(
            asr: SpeechRuntimeDescriptor(
                activeRuntimeID: "system-asr-fallback",
                preferredAssetID: conversationLanguage.bundledASRModelID,
                assetAvailability: .bundledMissing,
                fallbackReason: "Bundled ASR test asset is missing."
            ),
            tts: SpeechRuntimeDescriptor(
                activeRuntimeID: "system-tts-fallback",
                preferredAssetID: voiceBundle.localVoiceAssetID,
                assetAvailability: .bundledMissing,
                fallbackReason: "Bundled TTS test asset is missing."
            )
        )
    }

    func configureASR(localeIdentifier: String) {
        configuredASRLocaleIdentifier = localeIdentifier
    }

    func prepareASR(localeIdentifier: String) async throws {
        configuredASRLocaleIdentifier = localeIdentifier
    }

    func configureTTS(voiceBundle: VoiceBundle) {
        configuredVoiceBundleID = voiceBundle.id
    }

    func prepareTTS(voiceBundle: VoiceBundle) async throws {
        configuredVoiceBundleID = voiceBundle.id
    }

    func startListening() async throws {
        startListeningCount += 1
    }

    func stopListening() {}
    func suspendListening(reason: SpeechInterruptionReason) {}
    func recoverListeningIfNeeded() async throws {}
    func speak(chunks: [SpeechChunk], voiceStyle: VoiceStyle) async {}
    func interruptSpeech(reason: SpeechInterruptionReason) {}
}
