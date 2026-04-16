import Foundation

@MainActor
protocol DialogueRuntimeProtocol: AnyObject {
    func prepare(modelURL: URL, backend: InferenceBackendPreference) async throws
    func startConversation(preface: ConversationPreface, memoryContext: String, mode: ConversationMode) async throws
    func send(text: String) async throws -> String
    func sendStreaming(text: String, onToken: @escaping @MainActor (String) -> Void) async throws -> String
    func cancelCurrentResponse()
}

@MainActor
protocol InferenceEngineProtocol: DialogueRuntimeProtocol {}

@MainActor
protocol DuplexAudioRuntimeProtocol: AnyObject {
    var onInterruptionReason: (@MainActor (SpeechInterruptionReason) -> Void)? { get set }
    func prepareAudioSessionForCall() async throws
    func recoverAudioAfterInterruption() async throws
    func deactivateAudioSession()
}

@MainActor
protocol ASRRuntimeProtocol: AnyObject {
    var onPartialTranscript: (@MainActor (String) -> Void)? { get set }
    var onFinalTranscript: (@MainActor (String) -> Void)? { get set }
    var onVoiceActivity: (@MainActor (Double) -> Void)? { get set }
    var onVoiceActivityStateChange: (@MainActor (VoiceActivityState) -> Void)? { get set }
    var onRuntimeReadinessChange: (@MainActor (SpeechRuntimeReadiness) -> Void)? { get set }
    func configureASR(localeIdentifier: String)
    func prepareASR(localeIdentifier: String) async throws
    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus
    func startListening() async throws
    func stopListening()
    func suspendListening(reason: SpeechInterruptionReason)
    func recoverListeningIfNeeded() async throws
}

@MainActor
protocol TTSRuntimeProtocol: AnyObject {
    var onSpeechStateChange: (@MainActor (Bool) -> Void)? { get set }
    var onSpeechEnvelope: (@MainActor (Double) -> Void)? { get set }
    var onLipSyncFrame: (@MainActor (LipSyncFrame) -> Void)? { get set }
    func configureTTS(voiceBundle: VoiceBundle)
    func prepareTTS(voiceBundle: VoiceBundle) async throws
    func speak(chunks: [SpeechChunk], voiceStyle: VoiceStyle) async
    func speak(text: String, voiceStyle: VoiceStyle) async
    func interruptSpeech(reason: SpeechInterruptionReason)
}

@MainActor
protocol SpeechPipelineProtocol: DuplexAudioRuntimeProtocol, ASRRuntimeProtocol, TTSRuntimeProtocol {
    func runtimeStatus(
        conversationLanguage: LanguageProfile,
        voiceBundle: VoiceBundle
    ) -> SpeechRuntimeStatusSnapshot
}

@MainActor
protocol PostCallReviewRuntimeProtocol: AnyObject {
    func refineFeedback(
        _ feedback: FeedbackReport,
        for session: ConversationSession,
        learner: LearnerProfile
    ) async -> FeedbackReport
}

@MainActor
protocol CharacterRuntimeProtocol: AnyObject {
    func preload(characterBundle: CharacterBundle)
    func setCallState(_ state: AvatarState)
    func setSpeechEnvelope(_ envelope: Double)
    func setLipSyncFrame(_ frame: LipSyncFrame)
    func setEmotion(_ emotion: String)
    func setAttention(_ attention: Double)
    func teardown()
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

protocol UserDataStoreProtocol: Actor {
    func loadUserData() async throws -> UserDataSnapshot
    func saveUserData(_ snapshot: UserDataSnapshot) async throws
    func deleteAllUserData() async throws
}

protocol ModelStateStoreProtocol: Actor {
    func loadModelState() async throws -> ModelStateSnapshot
    func saveModelState(_ snapshot: ModelStateSnapshot) async throws
}

protocol AssetStateStoreProtocol: Actor {
    func loadAssetState() async throws -> AssetStateSnapshot
    func saveAssetState(_ snapshot: AssetStateSnapshot) async throws
    func recordValidationSnapshot(_ snapshot: ValidationRunSnapshot) async throws
}

extension TTSRuntimeProtocol {
    func speak(text: String, voiceStyle: VoiceStyle) async {
        await speak(chunks: [SpeechChunk(text: text)], voiceStyle: voiceStyle)
    }

    func interruptSpeech() {
        interruptSpeech(reason: .userRequested)
    }
}
