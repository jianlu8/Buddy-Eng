import Combine
import Foundation

@MainActor
final class ConversationOrchestrator: ObservableObject {
    struct SpeechChunker {
        private(set) var policy: SpeechChunkingPolicy
        private var buffer = ""

        init(policy: SpeechChunkingPolicy = .adaptive) {
            self.policy = policy
        }

        mutating func reset(policy: SpeechChunkingPolicy? = nil) {
            if let policy {
                self.policy = policy
            }
            buffer = ""
        }

        mutating func append(_ token: String) -> SpeechChunk? {
            if buffer.isEmpty {
                buffer = token
            } else if let lastCharacter = buffer.last,
                      let firstCharacter = token.first,
                      shouldInsertSpace(between: lastCharacter, and: firstCharacter) {
                buffer += " " + token
            } else {
                buffer += token
            }
            guard shouldFlush(afterAppending: token) else { return nil }
            return dequeueChunk(isFinal: false)
        }

        mutating func flushRemaining() -> SpeechChunk? {
            dequeueChunk(isFinal: true)
        }

        private mutating func dequeueChunk(isFinal: Bool) -> SpeechChunk? {
            let trimmedBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = ""
            guard trimmedBuffer.isEmpty == false else { return nil }
            return SpeechChunk(text: trimmedBuffer, isFinal: isFinal)
        }

        private func shouldFlush(afterAppending latestToken: String) -> Bool {
            let trimmedBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedBuffer.isEmpty == false else { return false }

            let endedSentence = latestToken.contains(".")
                || latestToken.contains("?")
                || latestToken.contains("!")
                || latestToken.contains("\n")
            let hitPhraseBoundary = latestToken.contains(",")
                || latestToken.contains(";")
                || latestToken.contains(":")
            let wordCount = trimmedBuffer.split(whereSeparator: \.isWhitespace).count

            switch policy {
            case .sentence:
                return endedSentence || trimmedBuffer.count >= 120
            case .phrase:
                if endedSentence {
                    return true
                }
                if hitPhraseBoundary && (trimmedBuffer.count >= 14 || wordCount >= 3) {
                    return true
                }
                return trimmedBuffer.count >= 64
            case .adaptive:
                if endedSentence {
                    return true
                }
                if hitPhraseBoundary && (trimmedBuffer.count >= 28 || wordCount >= 6) {
                    return true
                }
                return trimmedBuffer.count >= 72
            }
        }

        private func shouldInsertSpace(between left: Character, and right: Character) -> Bool {
            guard left.isWhitespace == false, right.isWhitespace == false else { return false }
            guard ",.;:!?)]}".contains(right) == false else { return false }
            guard "([{".contains(left) == false else { return false }
            return true
        }
    }

    @Published private(set) var phase: CallPhase = .idle
    @Published private(set) var avatarState: AvatarState = .idle
    @Published private(set) var activeSession: ConversationSession?
    @Published private(set) var activeMode: ConversationMode?
    @Published private(set) var inputMode: CallInputMode = .liveVoice
    @Published private(set) var visibleTurns: [ConversationTurn] = []
    @Published private(set) var liveUserTranscript = ""
    @Published private(set) var liveAssistantTranscript = ""
    @Published private(set) var latestFeedback: FeedbackReport?
    @Published private(set) var audioLevel: Double = 0
    @Published private(set) var lipSyncFrame: LipSyncFrame = .neutral
    @Published private(set) var subtitleOverlayState = SubtitleOverlayState()
    @Published private(set) var lastSpeechInterruption: SpeechInterruptionSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCallActive = false

    private let inferenceEngine: InferenceEngineProtocol
    private let speechPipeline: SpeechPipelineProtocol
    private let memoryStore: FileMemoryStore
    private let promptComposer: PromptComposer
    private let feedbackGenerator: FeedbackGenerator
    private let modelManager: ModelDownloadManager
    private let postCallReviewRuntime: PostCallReviewRuntimeProtocol
    private let performanceGovernor: PerformanceGovernor
    private let performanceTracer = CallPerformanceTracer()

    private struct ConversationActivationRequest {
        var preface: ConversationPreface
        var memoryContext: String
        var backend: InferenceBackendPreference
        var mode: ConversationMode
    }

    private var currentMode: ConversationMode = .chat
    private var speechChunker = SpeechChunker()
    private var spokenTextNormalizer = SpokenTextNormalizer()
    private var lastAssistantResponse = ""
    private var lastAssistantSpokenResponse = ""
    private var pendingAssistantSpokenRawBuffer = ""
    private var isAssistantSpeaking = false
    private var isGeneratingResponse = false
    private var activeResponseSessionID: UUID?
    private var didPersistCurrentAssistantTurn = false
    private var hasStartedOpeningTurn = false
    private var currentVoiceStyle: VoiceStyle = .default
    private var currentSpeechChunkingPolicy: SpeechChunkingPolicy = .adaptive
    private var pendingUserTranscripts: [String] = []
    private var pendingBargeInActivatedAt: Date?
    private var sessionBuffer: ConversationSession?
    private var lastUserTranscriptCommitAt: Date = .distantPast
    private var lastAssistantTranscriptCommitAt: Date = .distantPast
    private var pendingConversationActivation: ConversationActivationRequest?
    private var conversationActivationTask: Task<Void, Error>?
    private var ttsWarmupTask: Task<Void, Never>?

    init(
        inferenceEngine: InferenceEngineProtocol,
        speechPipeline: SpeechPipelineProtocol,
        memoryStore: FileMemoryStore,
        promptComposer: PromptComposer,
        feedbackGenerator: FeedbackGenerator,
        modelManager: ModelDownloadManager,
        postCallReviewRuntime: PostCallReviewRuntimeProtocol = LocalPostCallReviewRuntime(),
        performanceGovernor: PerformanceGovernor? = nil
    ) {
        self.inferenceEngine = inferenceEngine
        self.speechPipeline = speechPipeline
        self.memoryStore = memoryStore
        self.promptComposer = promptComposer
        self.feedbackGenerator = feedbackGenerator
        self.modelManager = modelManager
        self.postCallReviewRuntime = postCallReviewRuntime
        self.performanceGovernor = performanceGovernor ?? PerformanceGovernor()
        wireSpeechPipeline()
    }

    func beginPreparedCall(_ preparedCall: PreparedCallLaunch) {
        currentMode = preparedCall.mode
        setActiveMode(preparedCall.mode)
        setInputMode(preparedCall.inputMode)
        visibleTurns = []
        setLiveUserTranscript("")
        setLiveAssistantTranscript("")
        setLatestFeedback(nil)
        setErrorMessage(nil)
        lastAssistantResponse = ""
        lastAssistantSpokenResponse = ""
        didPersistCurrentAssistantTurn = false
        hasStartedOpeningTurn = false
        audioLevel = 0
        currentVoiceStyle = preparedCall.voiceStyle
        currentSpeechChunkingPolicy = preparedCall.speechChunkingPolicy
        speechChunker.reset(policy: preparedCall.speechChunkingPolicy)
        spokenTextNormalizer.reset()
        pendingAssistantSpokenRawBuffer = ""
        lastUserTranscriptCommitAt = .distantPast
        lastAssistantTranscriptCommitAt = .distantPast
        activeResponseSessionID = nil
        pendingUserTranscripts = []
        pendingBargeInActivatedAt = nil
        sessionBuffer = preparedCall.session
        activeSession = preparedCall.session
        pendingConversationActivation = ConversationActivationRequest(
            preface: preparedCall.conversationPreface,
            memoryContext: preparedCall.memoryContext,
            backend: preparedCall.inferenceBackend,
            mode: preparedCall.mode
        )
        conversationActivationTask?.cancel()
        conversationActivationTask = nil
        performanceTracer.begin(sessionID: preparedCall.session.id)
        setIsCallActive(true)
        setPhase(.listening)
        setAvatarState(preparedCall.inputMode == .liveVoice ? .listening : .idle)
        setLipSyncFrame(.neutral)
        subtitleOverlayState = SubtitleOverlayState()
        lastSpeechInterruption = nil
        queueTTSWarmupIfNeeded(for: preparedCall.voiceBundle)
    }

    func activateLiveAudioIfNeeded() async {
        guard inputMode == .liveVoice else { return }
        StartupTrace.mark("ConversationOrchestrator.activateLiveAudioIfNeeded.begin")

        do {
            try await speechPipeline.prepareAudioSessionForCall()
            StartupTrace.mark("ConversationOrchestrator.activateLiveAudioIfNeeded.audioSessionPrepared")
            try await speechPipeline.startListening()
            StartupTrace.mark("ConversationOrchestrator.activateLiveAudioIfNeeded.listeningStarted")
        } catch {
            StartupTrace.mark("ConversationOrchestrator.activateLiveAudioIfNeeded.degraded message=\(error.localizedDescription)")
            // Keep the call usable when local live audio cannot come up.
            speechPipeline.stopListening()
            speechPipeline.interruptSpeech(reason: .runtimeReset)
            setInputMode(.textAssisted)
            if phase == .listening {
                setPhase(.idle)
            }
            setAvatarState(.idle)
        }
    }

    func activateConversationIfNeeded() async throws {
        guard let activation = pendingConversationActivation else { return }

        if let conversationActivationTask {
            try await conversationActivationTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await self.inferenceEngine.prepare(
                modelURL: self.modelManager.modelURL,
                backend: activation.backend
            )
            StartupTrace.mark("ConversationOrchestrator.activateConversationIfNeeded.inferencePrepared backend=\(activation.backend.rawValue)")
            try Task.checkCancellation()
            try await self.inferenceEngine.startConversation(
                preface: activation.preface,
                memoryContext: activation.memoryContext,
                mode: activation.mode
            )
            StartupTrace.mark("ConversationOrchestrator.activateConversationIfNeeded.conversationStarted")
            await self.modelManager.markModelUsed()
            self.pendingConversationActivation = nil
        }

        conversationActivationTask = task
        defer { conversationActivationTask = nil }
        try await task.value
    }

    func failPreparedCall(message: String) {
        conversationActivationTask?.cancel()
        conversationActivationTask = nil
        ttsWarmupTask?.cancel()
        ttsWarmupTask = nil
        pendingConversationActivation = nil
        speechPipeline.stopListening()
        speechPipeline.interruptSpeech(reason: .runtimeReset)
        inferenceEngine.cancelCurrentResponse()
        activeSession = nil
        setActiveMode(nil)
        setIsCallActive(false)
        sessionBuffer = nil
        setPhase(.idle)
        setAvatarState(.idle)
        activeResponseSessionID = nil
        speechChunker.reset(policy: .adaptive)
        spokenTextNormalizer.reset()
        pendingAssistantSpokenRawBuffer = ""
        lastAssistantSpokenResponse = ""
        lastUserTranscriptCommitAt = .distantPast
        lastAssistantTranscriptCommitAt = .distantPast
        pendingUserTranscripts = []
        pendingBargeInActivatedAt = nil
        hasStartedOpeningTurn = false
        currentSpeechChunkingPolicy = .adaptive
        setErrorMessage(message)
        setLipSyncFrame(.neutral)
    }

    func endCall() async {
        guard var session = sessionBuffer ?? activeSession else { return }

        setPhase(.finishing)
        setIsCallActive(false)
        conversationActivationTask?.cancel()
        conversationActivationTask = nil
        ttsWarmupTask?.cancel()
        ttsWarmupTask = nil
        pendingConversationActivation = nil
        activeResponseSessionID = nil
        pendingUserTranscripts = []
        pendingBargeInActivatedAt = nil
        inferenceEngine.cancelCurrentResponse()
        speechPipeline.stopListening()
        speechPipeline.interruptSpeech(reason: .sessionEnded)
        session.endedAt = .now
        session.speechMetrics = performanceTracer.finalize()
        session.validationSnapshot = makeValidationSnapshot(for: session)
        let summary = feedbackGenerator.summarizeSession(session)
        session.summary = summary.summary
        session.keyMoments = summary.keyMoments

        let snapshot = await memoryStore.fetchSnapshot()
        let baseFeedback = feedbackGenerator.generateFeedback(for: session, learner: snapshot.learnerProfile, mode: currentMode)
        let feedback = await postCallReviewRuntime.refineFeedback(
            baseFeedback,
            for: session,
            learner: snapshot.learnerProfile
        )
        session.feedbackReport = feedback

        try? await memoryStore.upsertSession(session)
        try? await memoryStore.saveSessionFeedback(feedback, sessionID: session.id)

        setLatestFeedback(feedback)
        sessionBuffer = session
        activeSession = session
        setActiveMode(session.mode)
        setPhase(.idle)
        setAvatarState(.idle)
        setIsCallActive(false)
        setInputMode(.liveVoice)
        setLiveUserTranscript("")
        setLiveAssistantTranscript("")
        speechChunker.reset(policy: .adaptive)
        spokenTextNormalizer.reset()
        pendingAssistantSpokenRawBuffer = ""
        lastUserTranscriptCommitAt = .distantPast
        lastAssistantTranscriptCommitAt = .distantPast
        lastAssistantResponse = ""
        lastAssistantSpokenResponse = ""
        didPersistCurrentAssistantTurn = false
        hasStartedOpeningTurn = false
        currentSpeechChunkingPolicy = .adaptive
        setErrorMessage(nil)
        setLipSyncFrame(.neutral)
        subtitleOverlayState = SubtitleOverlayState()
        lastSpeechInterruption = nil
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
        setLatestFeedback(nil)
    }

    private func wireSpeechPipeline() {
        speechPipeline.onPartialTranscript = { [weak self] transcript in
            guard let self else { return }
            self.performanceTracer.markFirstPartialTranscriptIfNeeded(transcript)
            self.commitLiveUserTranscript(transcript)
            self.updateAudioLevel(max(self.audioLevel, 0.05))
            guard self.inputMode == .liveVoice else { return }
            guard self.isAssistantSpeaking else { return }
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 4 else { return }
            guard self.isLikelyEcho(trimmed) == false else { return }
            self.pendingBargeInActivatedAt = nil
            self.interruptAssistantForBargeIn()
        }

        speechPipeline.onFinalTranscript = { [weak self] transcript in
            guard let self else { return }
            Task { @MainActor in
                await self.handleFinalTranscript(transcript)
            }
        }

        speechPipeline.onVoiceActivity = { [weak self] level in
            guard let self else { return }
            self.updateAudioLevel(level)
            if level > 0.08 {
                self.performanceTracer.markUserSpeechStartIfNeeded()
            }
            guard self.inputMode == .liveVoice else { return }
            if self.phase == .listening {
                self.setAvatarState(level > 0.1 ? .listening : .idle)
            }
            guard self.isAssistantSpeaking else { return }
            guard let armedAt = self.pendingBargeInActivatedAt else { return }
            guard Date().timeIntervalSince(armedAt) >= 0.14 else { return }
            guard level >= 0.24 else { return }
            let transcript = self.liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard transcript.isEmpty || self.isLikelyEcho(transcript) == false else { return }
            self.pendingBargeInActivatedAt = nil
            self.interruptAssistantForBargeIn()
        }

        speechPipeline.onVoiceActivityStateChange = { [weak self] state in
            guard let self else { return }
            if state == .userSpeaking {
                self.performanceTracer.markUserSpeechStartIfNeeded()
            }
            guard self.inputMode == .liveVoice else {
                self.pendingBargeInActivatedAt = nil
                return
            }
            guard self.isAssistantSpeaking else {
                self.pendingBargeInActivatedAt = nil
                return
            }

            switch state {
            case .userSpeaking:
                if self.isLikelyEcho(self.liveUserTranscript) {
                    self.pendingBargeInActivatedAt = nil
                    return
                }

                let transcript = self.liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                if transcript.isEmpty == false, self.audioLevel >= 0.18 {
                    self.pendingBargeInActivatedAt = nil
                    self.interruptAssistantForBargeIn()
                } else {
                    self.pendingBargeInActivatedAt = .now
                }
            case .listening, .silent:
                self.pendingBargeInActivatedAt = nil
            }
        }

        speechPipeline.onSpeechStateChange = { [weak self] speaking in
            guard let self else { return }
            self.isAssistantSpeaking = speaking
            if speaking {
                self.performanceTracer.markAssistantSpeechStartIfNeeded()
                self.setPhase(.speaking)
                self.setAvatarState(.speaking)
            } else if self.isCallActive, self.isGeneratingResponse == false {
                self.setPhase(.listening)
                self.setAvatarState(self.inputMode == .liveVoice ? .listening : .idle)
            }
        }

        speechPipeline.onSpeechEnvelope = { [weak self] envelope in
            guard let self else { return }
            if self.isAssistantSpeaking {
                self.updateAudioLevel(envelope)
            }
        }

        speechPipeline.onLipSyncFrame = { [weak self] frame in
            guard let self else { return }
            self.performanceTracer.markFirstLipSyncFrameIfNeeded(frame)
            self.setLipSyncFrame(frame)
        }

        speechPipeline.onInterruptionReason = { [weak self] reason in
            guard let self else { return }
            if reason != .bargeIn {
                self.lastSpeechInterruption = SpeechInterruptionSnapshot(
                    reason: reason,
                    assistantText: self.liveAssistantTranscript,
                    userText: self.liveUserTranscript,
                    happenedAt: .now
                )
            }
        }
    }

    private func handleFinalTranscript(_ transcript: String) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard isLikelyEcho(trimmed) == false else { return }
        if isGeneratingResponse {
            enqueuePendingUserTranscript(trimmed)
            commitLiveUserTranscript(trimmed, force: true)
            return
        }
        setLiveUserTranscript("")

        let turn = ConversationTurn(role: .user, text: trimmed)
        visibleTurns.append(turn)
        await persistTurn(turn)

        await generateAssistantResponse(for: trimmed)
    }

    private func generateAssistantResponse(for text: String) async {
        isGeneratingResponse = true
        let responseSessionID = activeSession?.id
        activeResponseSessionID = responseSessionID
        setPhase(.thinking)
        setAvatarState(.thinking)
        setLiveAssistantTranscript("")
        setLipSyncFrame(.neutral)
        speechChunker.reset(policy: currentSpeechChunkingPolicy)
        spokenTextNormalizer.reset()
        pendingAssistantSpokenRawBuffer = ""
        lastAssistantTranscriptCommitAt = .distantPast
        lastAssistantResponse = ""
        lastAssistantSpokenResponse = ""
        didPersistCurrentAssistantTurn = false

        do {
            try await activateConversationIfNeeded()
            let response = try await inferenceEngine.sendStreaming(text: text) { [weak self] token in
                guard let self else { return }
                guard self.shouldApplyResponseUpdates(for: responseSessionID) else { return }
                self.lastAssistantResponse += token
                self.commitLiveAssistantTranscript(with: token)
                self.enqueueSpokenAssistantToken(token)
            }

            if shouldApplyResponseUpdates(for: responseSessionID) {
                setLiveAssistantTranscript(response)
                flushRemainingSpeech()
                await persistAssistantTurnIfNeeded(text: response, wasInterrupted: false)

                if isAssistantSpeaking == false {
                    setPhase(.listening)
                    setAvatarState(inputMode == .liveVoice ? .listening : .idle)
                }
            }
        } catch {
            if shouldApplyResponseUpdates(for: responseSessionID) {
                if isCancellationError(error) {
                    discardPendingSpokenText()
                    let partial = liveAssistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if partial.isEmpty == false {
                        await persistAssistantTurnIfNeeded(text: partial, wasInterrupted: true)
                    }
                    setPhase(.interrupted)
                    setAvatarState(.interrupted)
                } else {
                    discardPendingSpokenText()
                    setErrorMessage(error.localizedDescription)
                    setPhase(.error(error.localizedDescription))
                    setAvatarState(.error)
                }
            }
        }
        finishResponseGeneration(for: responseSessionID)
        if let pendingTranscript = dequeuePendingUserTranscript() {
            await handleFinalTranscript(pendingTranscript)
        }
    }

    private func interruptAssistantForBargeIn() {
        guard isAssistantSpeaking || isGeneratingResponse else { return }
        guard phase != .interrupted else { return }

        pendingBargeInActivatedAt = nil
        performanceTracer.markBargeInRequested()
        discardPendingSpokenText()
        lastSpeechInterruption = SpeechInterruptionSnapshot(
            reason: .bargeIn,
            assistantText: liveAssistantTranscript,
            userText: liveUserTranscript,
            happenedAt: .now
        )
        if liveAssistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            Task { @MainActor in
                await persistAssistantTurnIfNeeded(text: liveAssistantTranscript, wasInterrupted: true)
            }
        }
        inferenceEngine.cancelCurrentResponse()
        speechPipeline.interruptSpeech(reason: .bargeIn)
        performanceTracer.markBargeInStopped()
        subtitleOverlayState.primarySpeaker = .user
        if liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            subtitleOverlayState.liveText = liveUserTranscript
        }
        setPhase(.interrupted)
        setAvatarState(.interrupted)
    }

    private func enqueueSpokenAssistantToken(_ token: String) {
        pendingAssistantSpokenRawBuffer += token
        drainPendingSpokenText(finalize: false, allowSpeech: true)
    }

    private func drainPendingSpokenText(finalize: Bool, allowSpeech: Bool) {
        let result = spokenTextNormalizer.normalizeStreamingBuffer(
            &pendingAssistantSpokenRawBuffer,
            finalize: finalize
        )
        guard result.hasSpeakableContent else { return }

        if lastAssistantSpokenResponse.isEmpty {
            lastAssistantSpokenResponse = result.spokenText
        } else {
            lastAssistantSpokenResponse += " " + result.spokenText
        }

        guard allowSpeech else { return }
        flushSpeechIfNeeded(using: result.spokenText)
    }

    private func discardPendingSpokenText() {
        drainPendingSpokenText(finalize: true, allowSpeech: false)
        speechChunker.reset(policy: currentSpeechChunkingPolicy)
        spokenTextNormalizer.reset()
        pendingAssistantSpokenRawBuffer = ""
    }

    private func flushSpeechIfNeeded(using normalizedText: String) {
        guard let chunk = speechChunker.append(normalizedText) else { return }
        speakPreparedChunks([chunk])
    }

    private func flushRemainingSpeech() {
        drainPendingSpokenText(finalize: true, allowSpeech: true)
        guard let chunk = speechChunker.flushRemaining() else { return }
        speakPreparedChunks([chunk])
    }

    private func queueTTSWarmupIfNeeded(for voiceBundle: VoiceBundle) {
        ttsWarmupTask?.cancel()
        guard voiceBundle.prewarmRequired else {
            ttsWarmupTask = nil
            return
        }

        ttsWarmupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.speechPipeline.prepareTTS(voiceBundle: voiceBundle)
                StartupTrace.mark("ConversationOrchestrator.queueTTSWarmupIfNeeded.ready voice=\(voiceBundle.id)")
            } catch {
                StartupTrace.mark("ConversationOrchestrator.queueTTSWarmupIfNeeded.failed voice=\(voiceBundle.id) message=\(error.localizedDescription)")
            }
        }
    }

    private func speakPreparedChunks(_ chunks: [SpeechChunk]) {
        let voiceStyle = currentVoiceStyle
        let warmupTask = ttsWarmupTask
        Task { @MainActor [weak self] in
            guard let self else { return }
            await warmupTask?.value
            await self.speechPipeline.speak(chunks: chunks, voiceStyle: voiceStyle)
        }
    }

    private func isLikelyEcho(_ transcript: String) -> Bool {
        let normalized = transcript.lowercased()
        let rawAssistant = lastAssistantResponse.lowercased()
        let spokenAssistant = lastAssistantSpokenResponse.lowercased()
        let candidates = [rawAssistant, spokenAssistant].filter { $0.isEmpty == false }
        guard candidates.isEmpty == false else { return false }
        return candidates.contains { assistant in
            assistant.contains(normalized) || normalized.contains(assistant.suffix(24))
        }
    }

    private func persistAssistantTurnIfNeeded(text: String, wasInterrupted: Bool) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard didPersistCurrentAssistantTurn == false else { return }

        didPersistCurrentAssistantTurn = true
        let turn = ConversationTurn(role: .assistant, text: trimmed, wasInterrupted: wasInterrupted)
        visibleTurns.append(turn)
        await persistTurn(turn)
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == "LiteRTBridge" && nsError.code == 499
    }

    private func shouldApplyResponseUpdates(for sessionID: UUID?) -> Bool {
        guard isCallActive else { return false }
        guard activeResponseSessionID == sessionID else { return false }
        return sessionBuffer?.id == sessionID || activeSession?.id == sessionID
    }

    private func finishResponseGeneration(for sessionID: UUID?) {
        if activeResponseSessionID == sessionID {
            activeResponseSessionID = nil
        }
        isGeneratingResponse = false
        pendingBargeInActivatedAt = nil
        if isAssistantSpeaking == false {
            setLipSyncFrame(.neutral)
        }
    }

    private func enqueuePendingUserTranscript(_ transcript: String) {
        guard pendingUserTranscripts.last != transcript else { return }
        pendingUserTranscripts.append(transcript)
    }

    private func dequeuePendingUserTranscript() -> String? {
        guard isCallActive else {
            pendingUserTranscripts.removeAll()
            return nil
        }
        guard pendingUserTranscripts.isEmpty == false else { return nil }
        return pendingUserTranscripts.removeFirst()
    }

    private func updateAudioLevel(_ rawValue: Double) {
        let clamped = max(0, min(rawValue, 1))
        let step = max(0.02, performanceGovernor.profile.audioLevelQuantizationStep)
        let quantized = (clamped / step).rounded() * step
        guard abs(audioLevel - quantized) > 0.001 else { return }
        audioLevel = quantized
    }

    private func setPhase(_ newValue: CallPhase) {
        guard phase != newValue else { return }
        phase = newValue
    }

    private func setAvatarState(_ newValue: AvatarState) {
        guard avatarState != newValue else { return }
        avatarState = newValue
    }

    private func setActiveMode(_ newValue: ConversationMode?) {
        guard activeMode != newValue else { return }
        activeMode = newValue
    }

    private func setInputMode(_ newValue: CallInputMode) {
        guard inputMode != newValue else { return }
        inputMode = newValue
    }

    private func setLiveUserTranscript(_ newValue: String) {
        guard liveUserTranscript != newValue else { return }
        liveUserTranscript = newValue
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            subtitleOverlayState.primarySpeaker = .user
            subtitleOverlayState.liveText = newValue
        }
    }

    private func setLiveAssistantTranscript(_ newValue: String) {
        guard liveAssistantTranscript != newValue else { return }
        liveAssistantTranscript = newValue
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            performanceTracer.markFirstAssistantCaptionIfNeeded()
            subtitleOverlayState.primarySpeaker = .assistant
            subtitleOverlayState.liveText = newValue
        }
    }

    private func commitLiveUserTranscript(_ newValue: String, force: Bool = false) {
        guard shouldCommitTranscript(
            currentValue: liveUserTranscript,
            candidateValue: newValue,
            latestCommitAt: lastUserTranscriptCommitAt,
            minimumInterval: performanceGovernor.profile.userCaptionCommitInterval,
            minimumDelta: 5,
            force: force
        ) else { return }

        lastUserTranscriptCommitAt = .now
        setLiveUserTranscript(newValue)
    }

    private func commitLiveAssistantTranscript(with latestToken: String, force: Bool = false) {
        guard shouldCommitTranscript(
            currentValue: liveAssistantTranscript,
            candidateValue: lastAssistantResponse,
            latestCommitAt: lastAssistantTranscriptCommitAt,
            minimumInterval: performanceGovernor.profile.assistantCaptionCommitInterval,
            minimumDelta: 10,
            force: force || latestToken.contains(".") || latestToken.contains("?") || latestToken.contains("!") || latestToken.contains("\n")
        ) else { return }

        lastAssistantTranscriptCommitAt = .now
        setLiveAssistantTranscript(lastAssistantResponse)
    }

    private func shouldCommitTranscript(
        currentValue: String,
        candidateValue: String,
        latestCommitAt: Date,
        minimumInterval: TimeInterval,
        minimumDelta: Int,
        force: Bool
    ) -> Bool {
        guard currentValue != candidateValue else { return false }
        guard force == false else { return true }

        let currentLength = currentValue.count
        let candidateLength = candidateValue.count
        let delta = abs(candidateLength - currentLength)
        if currentLength == 0 || delta >= minimumDelta {
            return Date().timeIntervalSince(latestCommitAt) >= minimumInterval
        }
        return false
    }

    private func setLatestFeedback(_ newValue: FeedbackReport?) {
        guard latestFeedback != newValue else { return }
        latestFeedback = newValue
    }

    private func setErrorMessage(_ newValue: String?) {
        guard errorMessage != newValue else { return }
        errorMessage = newValue
    }

    private func setIsCallActive(_ newValue: Bool) {
        guard isCallActive != newValue else { return }
        isCallActive = newValue
    }

    func syncSubtitleOverlay(mode: SubtitleOverlayMode, dragOffset: Double, currentHeight: Double) {
        subtitleOverlayState.mode = mode
        subtitleOverlayState.dragOffset = dragOffset
        subtitleOverlayState.currentHeight = currentHeight
    }

    func recordSubtitleDragResponse(milliseconds: Int) {
        performanceTracer.recordSubtitleDragResponse(milliseconds: milliseconds)
    }

    func recordKeyboardOpenLatency(milliseconds: Int) {
        performanceTracer.recordKeyboardOpenLatency(milliseconds: milliseconds)
    }

    private func setLipSyncFrame(_ newValue: LipSyncFrame) {
        guard lipSyncFrame != newValue else { return }
        lipSyncFrame = newValue
    }

    private func persistTurn(_ turn: ConversationTurn) async {
        guard var session = sessionBuffer ?? activeSession else { return }
        session.turns.append(turn)
        sessionBuffer = session
        try? await memoryStore.upsertSession(session)
    }

    private func makeValidationSnapshot(for session: ConversationSession) -> ValidationRunSnapshot {
        let metrics = session.speechMetrics.last
        let measuredByID: [String: Int?] = [
            "first-caption": metrics?.callToFirstCaptionMs,
            "asr-partial": metrics?.speechToFirstPartialMs,
            "speech-start": metrics?.captionToSpeechStartMs,
            "barge-in-stop": metrics?.bargeInToStopMs,
            "lip-sync-delay": metrics?.lipSyncDelayMs,
            "subtitle-drag": metrics?.subtitleDragResponseMs,
            "keyboard-open": metrics?.keyboardOpenLatencyMs
        ]

        let budgetResults = ReleaseValidationSpec.current.budgets.map { budget in
            let measured = measuredByID[budget.id] ?? nil
            return ValidationBudgetResult(
                id: budget.id,
                title: budget.title,
                budgetMilliseconds: budget.budgetMilliseconds,
                measuredMilliseconds: measured,
                passed: measured.map { $0 <= budget.budgetMilliseconds }
            )
        }

        var blockingIssues: [String] = []
        if session.performanceSnapshot.speechRuntimeStatus.usesFallbackRuntime {
            blockingIssues.append("Speech runtime still fell back to system services.")
        }
        let failedBudgets = budgetResults
            .filter { $0.passed == false }
            .map(\.title)
        if failedBudgets.isEmpty == false {
            blockingIssues.append("Validation budgets exceeded: \(failedBudgets.joined(separator: ", ")).")
        }
        if session.turns.contains(where: { $0.role == .assistant }) == false {
            blockingIssues.append("No assistant turn was persisted for the call.")
        }

        return ValidationRunSnapshot(
            specVersionLabel: ReleaseValidationSpec.current.versionLabel,
            sessionID: session.id,
            budgetResults: budgetResults,
            blockingIssues: blockingIssues,
            overallPassed: blockingIssues.isEmpty
        )
    }
}
