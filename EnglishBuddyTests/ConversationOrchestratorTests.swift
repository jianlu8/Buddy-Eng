import XCTest
@testable import EnglishBuddyCore

@MainActor
final class ConversationOrchestratorTests: XCTestCase {
    func testSpokenTextNormalizerRemovesMarkdownAndEmoji() {
        var normalizer = SpokenTextNormalizer()
        var rawBuffer = "That’s *really* nice 😊"

        let result = normalizer.normalizeStreamingBuffer(&rawBuffer, finalize: true)

        XCTAssertEqual(result.spokenText, "That’s really nice")
        XCTAssertTrue(result.hasSpeakableContent)
        XCTAssertFalse(result.hasDeferredMarkup)
    }

    func testSpokenTextNormalizerConvertsOrderedListsIntoSpeech() {
        var normalizer = SpokenTextNormalizer()
        var rawBuffer = "1. Try shadowing. 2. Slow down."

        let result = normalizer.normalizeStreamingBuffer(&rawBuffer, finalize: true)

        XCTAssertEqual(result.spokenText, "First, try shadowing. Second, slow down.")
        XCTAssertTrue(result.suppressedCategories.contains(.listMarker))
    }

    func testSpokenTextNormalizerPreservesMarkdownLinkLabelOnly() {
        var normalizer = SpokenTextNormalizer()
        var rawBuffer = "[OpenAI](https://openai.com)"

        let result = normalizer.normalizeStreamingBuffer(&rawBuffer, finalize: true)

        XCTAssertEqual(result.spokenText, "OpenAI")
        XCTAssertTrue(result.suppressedCategories.contains(.links))
    }

    func testSpokenTextNormalizerSuppressesInlineCode() {
        var normalizer = SpokenTextNormalizer()
        var rawBuffer = "Use `print()` here"

        let result = normalizer.normalizeStreamingBuffer(&rawBuffer, finalize: true)

        XCTAssertEqual(result.spokenText, "Use here")
        XCTAssertTrue(result.suppressedCategories.contains(.code))
    }

    func testSpokenTextNormalizerSkipsFormattingPrefixes() {
        var normalizer = SpokenTextNormalizer()
        var rawBuffer = "### Tips\n- item\n> quote"

        let result = normalizer.normalizeStreamingBuffer(&rawBuffer, finalize: true)

        XCTAssertEqual(result.spokenText, "Tips item quote")
        XCTAssertTrue(result.suppressedCategories.contains(.markdownControl))
        XCTAssertTrue(result.suppressedCategories.contains(.listMarker))
    }

    func testSpeechChunkerSentencePolicyFlushesAtSentenceBoundary() {
        var chunker = ConversationOrchestrator.SpeechChunker(policy: .sentence)

        XCTAssertNil(chunker.append("Hello"))
        let chunk = chunker.append(" there.")

        XCTAssertEqual(chunk?.text, "Hello there.")
        XCTAssertEqual(chunk?.isFinal, false)
        XCTAssertNil(chunker.flushRemaining())
    }

    func testSpeechChunkerPhrasePolicyFlushesAtPhraseBoundary() {
        var chunker = ConversationOrchestrator.SpeechChunker(policy: .phrase)

        XCTAssertNil(chunker.append("Let us"))
        let chunk = chunker.append(" practice,")

        XCTAssertEqual(chunk?.text, "Let us practice,")
        XCTAssertEqual(chunk?.isFinal, false)
        XCTAssertNil(chunker.flushRemaining())
    }

    func testSpeechChunkerAdaptivePolicyWaitsForLongerPhraseBoundary() {
        var chunker = ConversationOrchestrator.SpeechChunker(policy: .adaptive)

        XCTAssertNil(chunker.append("Let us talk,"))
        XCTAssertNil(chunker.append(" but not flush yet"))
        let chunk = chunker.append(" because this is now comfortably long,")

        XCTAssertEqual(chunk?.text, "Let us talk, but not flush yet because this is now comfortably long,")
        XCTAssertEqual(chunk?.isFinal, false)
        XCTAssertNil(chunker.flushRemaining())
    }

    func testSpeechChunkerAdaptivePolicyDoesNotFlushOnWeakTrailingPhrase() {
        var chunker = ConversationOrchestrator.SpeechChunker(policy: .adaptive)

        XCTAssertNil(chunker.append("I can help you practice your English and answer your questions"))
        XCTAssertNil(chunker.append(" or just have a"))

        let chunk = chunker.append(" casual conversation!")

        XCTAssertEqual(
            chunk?.text,
            "I can help you practice your English and answer your questions or just have a casual conversation!"
        )
        XCTAssertEqual(chunk?.isFinal, false)
        XCTAssertNil(chunker.flushRemaining())
    }

    func testFallbackTextCreatesAssistantTurnUsingSelectedModel() async throws {
        let engine = MockInferenceEngine()
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(engine: engine, speech: speech)
        let orchestrator = harness.orchestrator
        let memoryStore = harness.memoryStore
        let session = harness.session

        await orchestrator.sendTextFallback("I like travel.")

        XCTAssertEqual(orchestrator.visibleTurns.count, 2)
        XCTAssertEqual(orchestrator.visibleTurns.first?.role, .user)
        XCTAssertEqual(orchestrator.visibleTurns.last?.role, .assistant)
        let snapshot = await memoryStore.fetchSnapshot()
        XCTAssertEqual(snapshot.sessions.first?.turns.count, 2)
        XCTAssertEqual(snapshot.sessions.first?.id, session.id)
    }

    func testQueuedTranscriptIsProcessedAfterActiveResponseFinishes() async throws {
        let engine = ControlledInferenceEngine()
        let harness = try await makeHarness(engine: engine, speech: MockSpeechPipeline())
        let orchestrator = harness.orchestrator

        let initialSend = Task {
            await orchestrator.sendTextFallback("Tell me about Seoul.")
        }

        await waitUntil { engine.hasPendingResponse }
        await orchestrator.sendTextFallback("Actually compare it with Tokyo.")
        XCTAssertEqual(orchestrator.visibleTurns.count, 1)
        XCTAssertEqual(orchestrator.visibleTurns.first?.text, "Tell me about Seoul.")

        engine.finishCurrentResponse(with: "Seoul feels energetic and compact.")
        await waitUntil { engine.streamingRequests.count == 2 }
        XCTAssertEqual(engine.streamingRequests.last, "Actually compare it with Tokyo.")

        engine.finishCurrentResponse(with: "Tokyo feels broader and more orderly.")
        await initialSend.value
        await Task.yield()

        XCTAssertEqual(
            orchestrator.visibleTurns.map(\.text),
            [
                "Tell me about Seoul.",
                "Seoul feels energetic and compact.",
                "Actually compare it with Tokyo.",
                "Tokyo feels broader and more orderly."
            ]
        )
    }

    func testOrchestratorUsesPreparedPhraseChunkingPolicyForStreamingSpeech() async throws {
        let engine = ControlledInferenceEngine()
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(
            engine: engine,
            speech: speech,
            speechChunkingPolicy: .phrase
        )
        let orchestrator = harness.orchestrator

        let sendTask = Task {
            await orchestrator.sendTextFallback("Coach me.")
        }

        await waitUntil { engine.hasPendingResponse }
        engine.emitLateToken("Let us")
        engine.emitLateToken(" practice,")
        await waitUntil { speech.spokenChunks.count == 1 }

        XCTAssertEqual(speech.spokenChunks.first?.text, "Let us practice,")
        XCTAssertEqual(speech.spokenChunks.first?.isFinal, false)

        engine.finishCurrentResponse(with: "Let us practice, slowly.")
        await sendTask.value
    }

    func testOrchestratorSanitizesStreamingMarkdownBeforeTTS() async throws {
        let engine = ControlledInferenceEngine()
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(
            engine: engine,
            speech: speech,
            speechChunkingPolicy: .phrase
        )
        let orchestrator = harness.orchestrator

        let sendTask = Task {
            await orchestrator.sendTextFallback("Say something natural.")
        }

        await waitUntil { engine.hasPendingResponse }
        engine.emitLateToken("That is *really")
        await Task.yield()
        XCTAssertTrue(speech.spokenChunks.isEmpty)

        engine.emitLateToken("* nice.")
        await waitUntil { speech.spokenChunks.count == 1 }

        XCTAssertEqual(speech.spokenChunks.first?.text, "That is really nice.")
        engine.finishCurrentResponse(with: "That is *really* nice.")
        await sendTask.value
    }

    func testOrchestratorDropsEmojiFromSpokenChunks() async throws {
        let engine = ControlledInferenceEngine()
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(engine: engine, speech: speech)
        let orchestrator = harness.orchestrator

        let sendTask = Task {
            await orchestrator.sendTextFallback("Say hello.")
        }

        await waitUntil { engine.hasPendingResponse }
        engine.emitLateToken("Nice 😊")
        engine.finishCurrentResponse(with: "Nice 😊")
        await sendTask.value
        await Task.yield()

        XCTAssertEqual(speech.spokenChunks.last?.text, "Nice")
        XCTAssertFalse(speech.spokenChunks.contains(where: { $0.text.contains("😊") }))
    }

    func testPreparedCallQueuesTTSWarmupForSelectedVoice() async throws {
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(engine: MockInferenceEngine(), speech: speech)
        _ = harness.orchestrator

        await waitUntil { speech.prepareTTSCount == 1 }

        XCTAssertEqual(speech.prepareTTSCount, 1)
    }

    func testEndCallCancelsActiveResponseAndIgnoresLateTokens() async throws {
        let engine = ControlledInferenceEngine()
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(engine: engine, speech: speech)
        let orchestrator = harness.orchestrator

        let sendTask = Task {
            await orchestrator.sendTextFallback("Walk me through this plan.")
        }

        await waitUntil { engine.hasPendingResponse }
        await orchestrator.endCall()

        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(speech.stopListeningCount, 1)
        XCTAssertEqual(speech.interruptSpeechCount, 1)
        XCTAssertFalse(orchestrator.isCallActive)
        XCTAssertEqual(orchestrator.visibleTurns.count, 1)
        XCTAssertEqual(orchestrator.liveAssistantTranscript, "")

        engine.emitLateToken("This token should be ignored.")
        engine.finishCurrentResponse(with: "This response should not persist.")
        await sendTask.value
        await Task.yield()

        XCTAssertEqual(orchestrator.visibleTurns.count, 1)
        XCTAssertEqual(orchestrator.visibleTurns.first?.text, "Walk me through this plan.")
        XCTAssertEqual(orchestrator.liveAssistantTranscript, "")
        XCTAssertNotNil(orchestrator.latestFeedback)
    }

    func testBargeInPreservesPartialAssistantTurn() async throws {
        let engine = ControlledInferenceEngine()
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(engine: engine, speech: speech)
        let orchestrator = harness.orchestrator

        let sendTask = Task {
            await orchestrator.sendTextFallback("Tell me something about Kyoto.")
        }

        await waitUntil { engine.hasPendingResponse }
        engine.emitLateToken("Kyoto feels calm.")
        speech.onSpeechStateChange?(true)
        speech.onPartialTranscript?("Actually compare it with Osaka.")
        speech.onVoiceActivityStateChange?(.userSpeaking)

        await Task.yield()
        engine.finishCurrentResponse(with: "Kyoto feels calm and traditional.")
        await sendTask.value
        await Task.yield()

        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(orchestrator.visibleTurns.filter { $0.role == .assistant }.count, 1)
        XCTAssertTrue(orchestrator.visibleTurns.contains(where: { $0.role == .assistant && $0.wasInterrupted }))
        XCTAssertEqual(
            orchestrator.visibleTurns.last(where: { $0.role == .assistant })?.text,
            "Kyoto feels calm."
        )
    }

    func testBargeInDoesNotSpeakDeferredMarkdownTail() async throws {
        let engine = ControlledInferenceEngine()
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(engine: engine, speech: speech)
        let orchestrator = harness.orchestrator

        let sendTask = Task {
            await orchestrator.sendTextFallback("Tell me something.")
        }

        await waitUntil { engine.hasPendingResponse }
        engine.emitLateToken("That feels *really")
        speech.onSpeechStateChange?(true)
        speech.onPartialTranscript?("Wait")
        speech.onVoiceActivityStateChange?(.userSpeaking)

        await Task.yield()
        XCTAssertTrue(speech.spokenChunks.isEmpty)

        engine.finishCurrentResponse(with: "That feels *really* calm.")
        await sendTask.value
    }

    func testEndCallPersistsSpeechMetricsFromCaptionSpeechAndLipSync() async throws {
        let engine = ControlledInferenceEngine()
        let speech = MockSpeechPipeline()
        let harness = try await makeHarness(engine: engine, speech: speech)
        let orchestrator = harness.orchestrator
        let memoryStore = harness.memoryStore

        let sendTask = Task {
            await orchestrator.sendTextFallback("Say hello.")
        }

        await waitUntil { engine.hasPendingResponse }
        speech.onVoiceActivityStateChange?(.userSpeaking)
        speech.onPartialTranscript?("Say hello.")
        engine.emitLateToken("Hello there.")
        speech.onSpeechStateChange?(true)
        speech.onLipSyncFrame?(LipSyncFrame(openness: 0.4, width: 0.3, jawOffset: 0.2, cheekLift: 0.1, timestamp: .now))
        engine.finishCurrentResponse(with: "Hello there.")
        await sendTask.value
        await orchestrator.endCall()

        let snapshot = await memoryStore.fetchSnapshot()
        let metrics = snapshot.sessions.first?.speechMetrics.first
        XCTAssertNotNil(metrics?.callToFirstCaptionMs)
        XCTAssertNotNil(metrics?.speechToFirstPartialMs)
        XCTAssertNotNil(metrics?.captionToSpeechStartMs)
        XCTAssertNotNil(metrics?.lipSyncDelayMs)
        XCTAssertEqual(
            snapshot.sessions.first?.validationSnapshot?.budgetResults.first(where: { $0.id == "asr-partial" })?.measuredMilliseconds,
            metrics?.speechToFirstPartialMs
        )
        XCTAssertNotNil(snapshot.sessions.first?.validationSnapshot)
    }

    func testEndTutorCallUsesPostCallReviewRuntimeRefinement() async throws {
        let engine = MockInferenceEngine()
        let speech = MockSpeechPipeline()
        let reviewRuntime = StubPostCallReviewRuntime()
        let harness = try await makeHarness(
            engine: engine,
            speech: speech,
            mode: .tutor,
            learningPlan: LearningFocusPlan(
                title: "Micro-goal for this call",
                mission: "Ask for help with one direct request.",
                checkpoint: "Add one clearer follow-up question.",
                successSignal: "One request and one reason.",
                pronunciationFocus: ["world"],
                carryOverVocabulary: ["clarify"]
            ),
            scenarioID: "travel-roleplay",
            postCallReviewRuntime: reviewRuntime
        )
        let orchestrator = harness.orchestrator

        await orchestrator.sendTextFallback("I need help with my booking.")
        await orchestrator.endCall()

        XCTAssertEqual(orchestrator.latestFeedback?.nextMission, reviewRuntime.refinedNextMission)
        XCTAssertEqual(orchestrator.latestFeedback?.continuationCue, reviewRuntime.refinedContinuationCue)
    }

    private func makeHarness(
        engine: any InferenceEngineProtocol,
        speech: MockSpeechPipeline,
        mode: ConversationMode = .chat,
        learningPlan: LearningFocusPlan? = nil,
        scenarioID: String? = nil,
        speechChunkingPolicy: SpeechChunkingPolicy = .adaptive,
        postCallReviewRuntime: PostCallReviewRuntimeProtocol = LocalPostCallReviewRuntime()
    ) async throws -> (orchestrator: ConversationOrchestrator, memoryStore: FileMemoryStore, session: ConversationSession) {
        let descriptor = ModelCatalog.current.defaultDescriptor
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let embeddedDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let embeddedModelURL = embeddedDirectoryURL.appendingPathComponent(descriptor.fileName)
        let embeddedMetadataURL = embeddedDirectoryURL.appendingPathComponent("EmbeddedModelMetadata.json")

        try FileManager.default.createDirectory(at: embeddedDirectoryURL, withIntermediateDirectories: true)
        let contents = Data("stub".utf8)
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
        let memoryStore = FileMemoryStore(filesystem: filesystem)
        try await memoryStore.load()

        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        await modelManager.refreshInstallState()
        let orchestrator = ConversationOrchestrator(
            inferenceEngine: engine,
            speechPipeline: speech,
            memoryStore: memoryStore,
            promptComposer: PromptComposer(),
            feedbackGenerator: FeedbackGenerator(),
            modelManager: modelManager,
            postCallReviewRuntime: postCallReviewRuntime
        )

        let session = ConversationSession(
            mode: mode,
            scenarioID: scenarioID,
            learningPlanSnapshot: learningPlan
        )
        let voiceBundle = VoiceCatalog.defaultBundle(
            for: CharacterCatalog.flagship.id,
            languageID: LanguageCatalog.english.id
        )
        try await memoryStore.upsertSession(session)
        orchestrator.beginPreparedCall(
            PreparedCallLaunch(
                mode: mode,
                session: session,
                inputMode: .liveVoice,
                openingInstruction: "Say hello.",
                voiceBundle: voiceBundle,
                voiceStyle: .default,
                speechChunkingPolicy: speechChunkingPolicy
            )
        )
        return (orchestrator, memoryStore, session)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while await condition() == false, DispatchTime.now().uptimeNanoseconds < deadline {
            await Task.yield()
        }
    }
}

private final class MockInferenceEngine: InferenceEngineProtocol {
    private(set) var preparedModelURL: URL?

    func prepare(modelURL: URL, backend: InferenceBackendPreference) async throws {
        preparedModelURL = modelURL
    }

    func startConversation(preface: ConversationPreface, memoryContext: String, mode: ConversationMode) async throws {}

    func send(text: String) async throws -> String {
        "Mock response for \(text)"
    }

    func sendStreaming(text: String, onToken: @escaping @MainActor (String) -> Void) async throws -> String {
        let response = "Mock response for \(text)"
        for token in response.split(separator: " ") {
            onToken(String(token) + " ")
        }
        return response
    }

    func cancelCurrentResponse() {}
}

@MainActor
private final class ControlledInferenceEngine: InferenceEngineProtocol {
    private(set) var streamingRequests: [String] = []
    private(set) var cancelCount = 0

    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var pendingTokenHandler: ((String) -> Void)?

    var hasPendingResponse: Bool {
        pendingContinuation != nil
    }

    func prepare(modelURL: URL, backend: InferenceBackendPreference) async throws {}
    func startConversation(preface: ConversationPreface, memoryContext: String, mode: ConversationMode) async throws {}
    func send(text: String) async throws -> String { text }

    func sendStreaming(text: String, onToken: @escaping @MainActor (String) -> Void) async throws -> String {
        streamingRequests.append(text)
        pendingTokenHandler = { token in
            onToken(token)
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation
        }
    }

    func cancelCurrentResponse() {
        cancelCount += 1
    }

    func emitLateToken(_ token: String) {
        pendingTokenHandler?(token)
    }

    func finishCurrentResponse(with response: String) {
        pendingContinuation?.resume(returning: response)
        pendingContinuation = nil
        pendingTokenHandler = nil
    }
}

private final class MockSpeechPipeline: SpeechPipelineProtocol {
    var onPartialTranscript: (@MainActor (String) -> Void)?
    var onFinalTranscript: (@MainActor (String) -> Void)?
    var onVoiceActivity: (@MainActor (Double) -> Void)?
    var onVoiceActivityStateChange: (@MainActor (VoiceActivityState) -> Void)?
    var onRuntimeReadinessChange: (@MainActor (SpeechRuntimeReadiness) -> Void)?
    var onSpeechStateChange: (@MainActor (Bool) -> Void)?
    var onSpeechEnvelope: (@MainActor (Double) -> Void)?
    var onLipSyncFrame: (@MainActor (LipSyncFrame) -> Void)?
    var onInterruptionReason: (@MainActor (SpeechInterruptionReason) -> Void)?
    private(set) var spokenChunks: [SpeechChunk] = []
    private(set) var stopListeningCount = 0
    private(set) var interruptSpeechCount = 0
    private(set) var prepareTTSCount = 0

    func prepareAudioSessionForCall() async throws {}
    func recoverAudioAfterInterruption() async throws {}
    func deactivateAudioSession() {}
    func configureASR(localeIdentifier: String) {}
    func prepareASR(localeIdentifier: String) async throws {}
    func configureTTS(voiceBundle: VoiceBundle) {}
    func prepareTTS(voiceBundle: VoiceBundle) async throws { prepareTTSCount += 1 }
    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus { .ready }
    func runtimeStatus(
        conversationLanguage: LanguageProfile,
        voiceBundle: VoiceBundle
    ) -> SpeechRuntimeStatusSnapshot { .fallbackDefault }
    func startListening() async throws {}
    func stopListening() { stopListeningCount += 1 }
    func suspendListening(reason: SpeechInterruptionReason) {}
    func recoverListeningIfNeeded() async throws {}
    func speak(chunks: [SpeechChunk], voiceStyle: VoiceStyle) async {
        spokenChunks.append(contentsOf: chunks)
    }
    func interruptSpeech(reason: SpeechInterruptionReason) {
        interruptSpeechCount += 1
        onInterruptionReason?(reason)
        onSpeechStateChange?(false)
    }
}

@MainActor
private final class StubPostCallReviewRuntime: PostCallReviewRuntimeProtocol {
    let refinedNextMission = "Stubbed tutor review mission."
    let refinedContinuationCue = "Stubbed tutor continuation cue."

    func refineFeedback(
        _ feedback: FeedbackReport,
        for session: ConversationSession,
        learner: LearnerProfile
    ) async -> FeedbackReport {
        var refined = feedback
        if session.mode == .tutor {
            refined.nextMission = refinedNextMission
            refined.continuationCue = refinedContinuationCue
        }
        return refined
    }
}
