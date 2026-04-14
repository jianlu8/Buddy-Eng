import Combine
import Foundation

@MainActor
final class ConversationOrchestrator: ObservableObject {
    @Published private(set) var phase: CallPhase = .idle
    @Published private(set) var avatarState: AvatarState = .idle
    @Published private(set) var activeSession: ConversationSession?
    @Published private(set) var activeMode: ConversationMode?
    @Published private(set) var inputMode: CallInputMode = .liveVoice
    @Published private(set) var visibleTurns: [ConversationTurn] = []
    @Published private(set) var liveUserTranscript = ""
    @Published private(set) var liveAssistantTranscript = ""
    @Published private(set) var subtitleSpeaker: SubtitleSpeaker = .assistant
    @Published private(set) var latestFeedback: FeedbackReport?
    @Published private(set) var audioLevel: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCallActive = false

    private let inferenceEngine: InferenceEngineProtocol
    private let speechPipeline: SpeechPipelineProtocol
    private let memoryStore: FileMemoryStore
    private let promptComposer: PromptComposer
    private let feedbackGenerator: FeedbackGenerator
    private let modelManager: ModelDownloadManager

    private var currentMode: ConversationMode = .chat
    private var speechQueueBuffer = ""
    private var lastAssistantResponse = ""
    private var isAssistantSpeaking = false
    private var isGeneratingResponse = false
    private var didPersistCurrentAssistantTurn = false
    private var hasStartedOpeningTurn = false
    private var currentVoiceStyle: VoiceStyle = .default

    init(
        inferenceEngine: InferenceEngineProtocol,
        speechPipeline: SpeechPipelineProtocol,
        memoryStore: FileMemoryStore,
        promptComposer: PromptComposer,
        feedbackGenerator: FeedbackGenerator,
        modelManager: ModelDownloadManager
    ) {
        self.inferenceEngine = inferenceEngine
        self.speechPipeline = speechPipeline
        self.memoryStore = memoryStore
        self.promptComposer = promptComposer
        self.feedbackGenerator = feedbackGenerator
        self.modelManager = modelManager
        wireSpeechPipeline()
    }

    func beginPreparedCall(_ preparedCall: PreparedCallLaunch) {
        currentMode = preparedCall.mode
        activeMode = preparedCall.mode
        inputMode = preparedCall.inputMode
        visibleTurns = []
        liveUserTranscript = ""
        liveAssistantTranscript = ""
        subtitleSpeaker = .assistant
        latestFeedback = nil
        errorMessage = nil
        speechQueueBuffer = ""
        lastAssistantResponse = ""
        didPersistCurrentAssistantTurn = false
        hasStartedOpeningTurn = false
        audioLevel = 0
        currentVoiceStyle = preparedCall.voiceStyle
        activeSession = preparedCall.session
        isCallActive = true
        phase = .listening
        avatarState = preparedCall.inputMode == .liveVoice ? .listening : .idle
    }

    func failPreparedCall(message: String) {
        speechPipeline.stopListening()
        speechPipeline.interruptSpeech()
        inferenceEngine.cancelCurrentResponse()
        activeSession = nil
        activeMode = nil
        isCallActive = false
        phase = .idle
        avatarState = .idle
        hasStartedOpeningTurn = false
        errorMessage = message
    }

    func endCall() async {
        guard var session = activeSession else { return }

        phase = .finishing
        speechPipeline.stopListening()
        speechPipeline.interruptSpeech()
        session.endedAt = .now
        let summary = feedbackGenerator.summarizeSession(session)
        session.summary = summary.summary
        session.keyMoments = summary.keyMoments

        let snapshot = await memoryStore.fetchSnapshot()
        let feedback = feedbackGenerator.generateFeedback(for: session, learner: snapshot.learnerProfile, mode: currentMode)
        session.feedbackReport = feedback

        try? await memoryStore.upsertSession(session)
        try? await memoryStore.saveSessionFeedback(feedback, sessionID: session.id)

        latestFeedback = feedback
        activeSession = session
        activeMode = session.mode
        phase = .idle
        avatarState = .idle
        isCallActive = false
        inputMode = .liveVoice
        liveUserTranscript = ""
        liveAssistantTranscript = ""
        subtitleSpeaker = .assistant
        speechQueueBuffer = ""
        lastAssistantResponse = ""
        didPersistCurrentAssistantTurn = false
        hasStartedOpeningTurn = false
        errorMessage = nil
    }

    func startOpeningTurnIfNeeded(_ instruction: String) async {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard isCallActive else { return }
        guard hasStartedOpeningTurn == false else { return }
        guard visibleTurns.isEmpty else { return }
        guard isGeneratingResponse == false else { return }

        hasStartedOpeningTurn = true
        await generateAssistantResponse(for: trimmed)
    }

    func sendTextFallback(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        await handleFinalTranscript(trimmed)
    }

    func clearLatestFeedback() {
        latestFeedback = nil
    }

    private func wireSpeechPipeline() {
        speechPipeline.onPartialTranscript = { [weak self] transcript in
            guard let self else { return }
            self.liveUserTranscript = transcript
            self.subtitleSpeaker = .user
            self.audioLevel = max(self.audioLevel, 0.05)

            guard self.inputMode == .liveVoice else { return }
            if self.isAssistantSpeaking, self.isLikelyEcho(transcript) == false, transcript.count >= 8 {
                self.interruptAssistantForBargeIn()
            }
        }

        speechPipeline.onFinalTranscript = { [weak self] transcript in
            guard let self else { return }
            Task { @MainActor in
                await self.handleFinalTranscript(transcript)
            }
        }

        speechPipeline.onVoiceActivity = { [weak self] level in
            guard let self else { return }
            self.audioLevel = level
            guard self.inputMode == .liveVoice else { return }
            if self.phase == .listening {
                self.avatarState = level > 0.1 ? .listening : .idle
                self.subtitleSpeaker = level > 0.1 ? .user : .assistant
            }
        }

        speechPipeline.onSpeechStateChange = { [weak self] speaking in
            guard let self else { return }
            self.isAssistantSpeaking = speaking
            if speaking {
                self.phase = .speaking
                self.avatarState = .speaking
            } else if self.isCallActive, self.isGeneratingResponse == false {
                self.phase = .listening
                self.avatarState = self.inputMode == .liveVoice ? .listening : .idle
            }
        }
    }

    private func handleFinalTranscript(_ transcript: String) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard isLikelyEcho(trimmed) == false else { return }
        guard isGeneratingResponse == false else { return }
        liveUserTranscript = ""
        subtitleSpeaker = .assistant

        let turn = ConversationTurn(role: .user, text: trimmed)
        visibleTurns.append(turn)

        if var session = activeSession {
            session.turns.append(turn)
            activeSession = session
            try? await memoryStore.saveTurn(turn, sessionID: session.id)
            try? await memoryStore.upsertSession(session)
        }

        await generateAssistantResponse(for: trimmed)
    }

    private func generateAssistantResponse(for text: String) async {
        isGeneratingResponse = true
        phase = .thinking
        avatarState = .thinking
        liveAssistantTranscript = ""
        subtitleSpeaker = .assistant
        speechQueueBuffer = ""
        lastAssistantResponse = ""
        didPersistCurrentAssistantTurn = false

        do {
            let response = try await inferenceEngine.sendStreaming(text: text) { [weak self] token in
                guard let self else { return }
                self.lastAssistantResponse += token
                self.liveAssistantTranscript = self.lastAssistantResponse
                self.subtitleSpeaker = .assistant
                self.flushSpeechIfNeeded(using: token)
            }

            liveAssistantTranscript = response
            flushRemainingSpeech()

            await persistAssistantTurnIfNeeded(text: response, wasInterrupted: false)

            if isAssistantSpeaking == false {
                phase = .listening
                avatarState = inputMode == .liveVoice ? .listening : .idle
            }
        } catch {
            if isCancellationError(error) {
                let partial = liveAssistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                if partial.isEmpty == false {
                    await persistAssistantTurnIfNeeded(text: partial, wasInterrupted: true)
                }
                phase = .interrupted
                avatarState = .interrupted
            } else {
                errorMessage = error.localizedDescription
                phase = .error(error.localizedDescription)
                avatarState = .error
            }
        }
        isGeneratingResponse = false
    }

    private func interruptAssistantForBargeIn() {
        if liveAssistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            Task { @MainActor in
                await persistAssistantTurnIfNeeded(text: liveAssistantTranscript, wasInterrupted: true)
            }
        }
        inferenceEngine.cancelCurrentResponse()
        speechPipeline.interruptSpeech()
        phase = .interrupted
        avatarState = .interrupted
    }

    private func flushSpeechIfNeeded(using latestToken: String) {
        speechQueueBuffer += latestToken
        let shouldFlush = latestToken.contains(".") || latestToken.contains("?") || latestToken.contains("!") || speechQueueBuffer.count > 90
        guard shouldFlush else { return }
        let chunk = speechQueueBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        speechQueueBuffer = ""
        Task {
            await speechPipeline.speak(text: chunk, voiceStyle: currentVoiceStyle)
        }
    }

    private func flushRemainingSpeech() {
        let chunk = speechQueueBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        speechQueueBuffer = ""
        guard chunk.isEmpty == false else { return }
        Task {
            await speechPipeline.speak(text: chunk, voiceStyle: currentVoiceStyle)
        }
    }

    private func isLikelyEcho(_ transcript: String) -> Bool {
        let normalized = transcript.lowercased()
        let assistant = lastAssistantResponse.lowercased()
        guard assistant.isEmpty == false else { return false }
        return assistant.contains(normalized) || normalized.contains(assistant.suffix(24))
    }

    private func persistAssistantTurnIfNeeded(text: String, wasInterrupted: Bool) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard didPersistCurrentAssistantTurn == false else { return }

        didPersistCurrentAssistantTurn = true
        let turn = ConversationTurn(role: .assistant, text: trimmed, wasInterrupted: wasInterrupted)
        visibleTurns.append(turn)

        if var session = activeSession {
            session.turns.append(turn)
            activeSession = session
            try? await memoryStore.saveTurn(turn, sessionID: session.id)
            try? await memoryStore.upsertSession(session)
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == "LiteRTBridge" && nsError.code == 499
    }
}
