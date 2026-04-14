import Foundation

@MainActor
protocol InferenceEngineProtocol: AnyObject {
    func prepare(modelURL: URL, backend: InferenceBackendPreference) async throws
    func startConversation(preface: ConversationPreface, memoryContext: String, mode: ConversationMode) async throws
    func send(text: String) async throws -> String
    func sendStreaming(text: String, onToken: @escaping @MainActor (String) -> Void) async throws -> String
    func cancelCurrentResponse()
}

@MainActor
protocol SpeechPipelineProtocol: AnyObject {
    var onPartialTranscript: (@MainActor (String) -> Void)? { get set }
    var onFinalTranscript: (@MainActor (String) -> Void)? { get set }
    var onVoiceActivity: (@MainActor (Double) -> Void)? { get set }
    var onSpeechStateChange: (@MainActor (Bool) -> Void)? { get set }
    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus
    func startListening() async throws
    func stopListening()
    func speak(text: String, voiceStyle: VoiceStyle) async
    func interruptSpeech()
}

protocol MemoryStore: Actor {
    func load() async throws
    func fetchSnapshot() -> MemorySnapshot
    func fetchPersonaSummary() -> String
    func fetchLearningContext() -> String
    func saveTurn(_ turn: ConversationTurn, sessionID: UUID) async throws
    func saveSessionFeedback(_ feedback: FeedbackReport, sessionID: UUID) async throws
    func upsertSession(_ session: ConversationSession) async throws
    func updateLearnerProfile(_ mutate: @Sendable (inout LearnerProfile) -> Void) async throws
    func updateCompanionSettings(_ mutate: @Sendable (inout CompanionSettings) -> Void) async throws
    func upsertVocabulary(_ vocabulary: [VocabularyItem]) async throws
    func deleteAllMemory() async throws
}
