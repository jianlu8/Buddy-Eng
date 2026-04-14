import XCTest
@testable import EnglishBuddyCore

@MainActor
final class ConversationOrchestratorTests: XCTestCase {
    func testFallbackTextCreatesAssistantTurnUsingSelectedModel() async throws {
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

        let engine = MockInferenceEngine()
        let speech = MockSpeechPipeline()
        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        await modelManager.refreshInstallState()
        let orchestrator = ConversationOrchestrator(
            inferenceEngine: engine,
            speechPipeline: speech,
            memoryStore: memoryStore,
            promptComposer: PromptComposer(),
            feedbackGenerator: FeedbackGenerator(),
            modelManager: modelManager
        )

        let session = ConversationSession(mode: .chat)
        try await memoryStore.upsertSession(session)
        orchestrator.beginPreparedCall(
            PreparedCallLaunch(
                mode: .chat,
                session: session,
                inputMode: .liveVoice,
                openingInstruction: "Say hello.",
                voiceStyle: .default
            )
        )
        await orchestrator.sendTextFallback("I like travel.")

        XCTAssertEqual(orchestrator.visibleTurns.count, 2)
        XCTAssertEqual(orchestrator.visibleTurns.first?.role, .user)
        XCTAssertEqual(orchestrator.visibleTurns.last?.role, .assistant)
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

private final class MockSpeechPipeline: SpeechPipelineProtocol {
    var onPartialTranscript: (@MainActor (String) -> Void)?
    var onFinalTranscript: (@MainActor (String) -> Void)?
    var onVoiceActivity: (@MainActor (Double) -> Void)?
    var onSpeechStateChange: (@MainActor (Bool) -> Void)?

    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus { .ready }
    func startListening() async throws {}
    func stopListening() {}
    func speak(text: String, voiceStyle: VoiceStyle) async {}
    func interruptSpeech() {}
}
