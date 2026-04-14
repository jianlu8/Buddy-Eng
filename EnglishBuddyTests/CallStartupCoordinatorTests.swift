import XCTest
@testable import EnglishBuddyCore

@MainActor
final class CallStartupCoordinatorTests: XCTestCase {
    func testPrepareCallReturnsReadyAndStartsVoiceListening() async throws {
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
        XCTAssertEqual(speech.startListeningCount, 1)
        XCTAssertEqual(inference.preparedModelURL, filesystem.embeddedModelURL(for: ModelCatalog.current.defaultDescriptor))
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
    var onSpeechStateChange: (@MainActor (Bool) -> Void)?

    var capabilityStatus: SpeechCapabilityStatus
    private(set) var startListeningCount = 0

    init(capabilityStatus: SpeechCapabilityStatus = .ready) {
        self.capabilityStatus = capabilityStatus
    }

    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus {
        capabilityStatus
    }

    func startListening() async throws {
        startListeningCount += 1
    }

    func stopListening() {}
    func speak(text: String, voiceStyle: VoiceStyle) async {}
    func interruptSpeech() {}
}
