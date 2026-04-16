import Foundation

@MainActor
final class LiveSpeechPipeline: SpeechPipelineProtocol {
    var onPartialTranscript: (@MainActor (String) -> Void)?
    var onFinalTranscript: (@MainActor (String) -> Void)?
    var onVoiceActivity: (@MainActor (Double) -> Void)?
    var onVoiceActivityStateChange: (@MainActor (VoiceActivityState) -> Void)?
    var onRuntimeReadinessChange: (@MainActor (SpeechRuntimeReadiness) -> Void)?
    var onSpeechStateChange: (@MainActor (Bool) -> Void)?
    var onSpeechEnvelope: (@MainActor (Double) -> Void)?
    var onLipSyncFrame: (@MainActor (LipSyncFrame) -> Void)?
    var onInterruptionReason: (@MainActor (SpeechInterruptionReason) -> Void)?

    private let audioRuntime: DuplexAudioRuntime
    private let speechAssetRegistry: BundledSpeechAssetRegistry
    private let runtimeFactory: SpeechRuntimeFactory
    private var asrRuntime: any ASRRuntimeProtocol
    private var ttsRuntime: any TTSRuntimeProtocol
    private let usesInjectedASRRuntime: Bool
    private let usesInjectedTTSRuntime: Bool
    private var currentASRDescriptor: SpeechRuntimeDescriptor?
    private var currentTTSDescriptor: SpeechRuntimeDescriptor?

    init(
        filesystem: AppFilesystem = AppFilesystem(),
        audioRuntime: DuplexAudioRuntime = DuplexAudioRuntime(),
        speechAssetRegistry: BundledSpeechAssetRegistry? = nil,
        runtimeFactory: SpeechRuntimeFactory? = nil,
        asrRuntime: (any ASRRuntimeProtocol)? = nil,
        ttsRuntime: (any TTSRuntimeProtocol)? = nil
    ) {
        let resolvedSpeechAssetRegistry = speechAssetRegistry ?? BundledSpeechAssetRegistry(filesystem: filesystem)
        let resolvedRuntimeFactory = runtimeFactory ?? SpeechRuntimeFactory(
            audioRuntime: audioRuntime,
            assetRegistry: resolvedSpeechAssetRegistry
        )
        let usesInjectedASRRuntime = asrRuntime != nil
        let usesInjectedTTSRuntime = ttsRuntime != nil
        self.audioRuntime = audioRuntime
        self.speechAssetRegistry = resolvedSpeechAssetRegistry
        self.runtimeFactory = resolvedRuntimeFactory
        self.usesInjectedASRRuntime = usesInjectedASRRuntime
        self.usesInjectedTTSRuntime = usesInjectedTTSRuntime
        self.currentASRDescriptor = usesInjectedASRRuntime ? nil : SpeechRuntimeStatusSnapshot.fallbackDefault.asr
        self.currentTTSDescriptor = usesInjectedTTSRuntime ? nil : SpeechRuntimeStatusSnapshot.fallbackDefault.tts
        self.asrRuntime = asrRuntime ?? resolvedRuntimeFactory.makeASRRuntime()
        self.ttsRuntime = ttsRuntime ?? resolvedRuntimeFactory.makeTTSRuntime()
        wireASRRuntime()
        wireTTSRuntime()
        wireAudioRuntime()
    }

    func configureASR(localeIdentifier: String) {
        refreshASRRuntimeIfNeeded(localeIdentifier: localeIdentifier)
        asrRuntime.configureASR(localeIdentifier: localeIdentifier)
    }

    func prepareASR(localeIdentifier: String) async throws {
        refreshASRRuntimeIfNeeded(localeIdentifier: localeIdentifier)
        try await asrRuntime.prepareASR(localeIdentifier: localeIdentifier)
    }

    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus {
        await asrRuntime.evaluateSpeechCapability(requestPermissions: requestPermissions)
    }

    func startListening() async throws {
        try await asrRuntime.startListening()
    }

    func stopListening() {
        asrRuntime.stopListening()
        audioRuntime.deactivateAudioSession()
    }

    func suspendListening(reason: SpeechInterruptionReason) {
        asrRuntime.suspendListening(reason: reason)
    }

    func recoverListeningIfNeeded() async throws {
        try await asrRuntime.recoverListeningIfNeeded()
    }

    func configureTTS(voiceBundle: VoiceBundle) {
        refreshTTSRuntimeIfNeeded(voiceBundle: voiceBundle)
        ttsRuntime.configureTTS(voiceBundle: voiceBundle)
    }

    func prepareTTS(voiceBundle: VoiceBundle) async throws {
        refreshTTSRuntimeIfNeeded(voiceBundle: voiceBundle)
        try await ttsRuntime.prepareTTS(voiceBundle: voiceBundle)
    }

    func speak(chunks: [SpeechChunk], voiceStyle: VoiceStyle) async {
        await ttsRuntime.speak(chunks: chunks, voiceStyle: voiceStyle)
    }

    func interruptSpeech(reason: SpeechInterruptionReason) {
        ttsRuntime.interruptSpeech(reason: reason)
        onInterruptionReason?(reason)
    }

    func prepareAudioSessionForCall() async throws {
        try await audioRuntime.prepareAudioSessionForCall()
    }

    func recoverAudioAfterInterruption() async throws {
        try await audioRuntime.recoverAudioAfterInterruption()
        try await recoverListeningIfNeeded()
    }

    func deactivateAudioSession() {
        audioRuntime.deactivateAudioSession()
    }

    func runtimeStatus(
        conversationLanguage: LanguageProfile,
        voiceBundle: VoiceBundle
    ) -> SpeechRuntimeStatusSnapshot {
        runtimeFactory.runtimeStatus(
            conversationLanguage: conversationLanguage,
            voiceBundle: voiceBundle
        )
    }

    private func refreshASRRuntimeIfNeeded(localeIdentifier: String) {
        guard usesInjectedASRRuntime == false else { return }
        let descriptor = runtimeFactory.asrRuntimeDescriptor(localeIdentifier: localeIdentifier)
        guard descriptor != currentASRDescriptor else { return }
        currentASRDescriptor = descriptor
        asrRuntime = runtimeFactory.makeASRRuntime(descriptor: descriptor)
        wireASRRuntime()
    }

    private func refreshTTSRuntimeIfNeeded(voiceBundle: VoiceBundle) {
        guard usesInjectedTTSRuntime == false else { return }
        let descriptor = runtimeFactory.ttsRuntimeDescriptor(voiceBundle: voiceBundle)
        guard descriptor != currentTTSDescriptor else { return }
        currentTTSDescriptor = descriptor
        ttsRuntime = runtimeFactory.makeTTSRuntime(descriptor: descriptor)
        wireTTSRuntime()
    }

    private func wireASRRuntime() {
        asrRuntime.onPartialTranscript = { [weak self] transcript in
            self?.onPartialTranscript?(transcript)
        }
        asrRuntime.onFinalTranscript = { [weak self] transcript in
            self?.onFinalTranscript?(transcript)
        }
        asrRuntime.onVoiceActivity = { [weak self] level in
            self?.onVoiceActivity?(level)
        }
        asrRuntime.onVoiceActivityStateChange = { [weak self] state in
            self?.onVoiceActivityStateChange?(state)
        }
        asrRuntime.onRuntimeReadinessChange = { [weak self] readiness in
            self?.onRuntimeReadinessChange?(readiness)
        }
    }

    private func wireTTSRuntime() {
        ttsRuntime.onSpeechStateChange = { [weak self] speaking in
            self?.onSpeechStateChange?(speaking)
        }
        ttsRuntime.onSpeechEnvelope = { [weak self] envelope in
            self?.onSpeechEnvelope?(envelope)
        }
        ttsRuntime.onLipSyncFrame = { [weak self] frame in
            self?.onLipSyncFrame?(frame)
        }
    }

    private func wireAudioRuntime() {
        audioRuntime.onInterruptionReason = { [weak self] reason in
            self?.onInterruptionReason?(reason)
        }
        audioRuntime.onListeningSuspended = { [weak self] reason in
            guard let self else { return }
            self.asrRuntime.suspendListening(reason: reason)
            self.ttsRuntime.interruptSpeech(reason: reason)
            self.onVoiceActivity?(0)
            self.onInterruptionReason?(reason)
        }
        audioRuntime.onRecoveryRequested = { [weak self] in
            guard let self else { return }
            try? await self.recoverAudioAfterInterruption()
        }
    }
}
