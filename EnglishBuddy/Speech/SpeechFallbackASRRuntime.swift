import AVFoundation
import Speech

private final class SpeechFallbackASRRealtimeBridge: @unchecked Sendable {
    typealias VoiceLevelPublisher = @Sendable (Double) -> Void

    private let request: SFSpeechAudioBufferRecognitionRequest
    private let publishVoiceLevel: VoiceLevelPublisher

    init(
        request: SFSpeechAudioBufferRecognitionRequest,
        publishVoiceLevel: @escaping VoiceLevelPublisher
    ) {
        self.request = request
        self.publishVoiceLevel = publishVoiceLevel
    }

    func handle(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        request.append(buffer)
        publishVoiceLevel(SpeechFallbackASRRuntime.computeLevel(for: buffer))
    }

    nonisolated static func makeTapBlock(for bridge: SpeechFallbackASRRealtimeBridge) -> AVAudioNodeTapBlock {
        { buffer, _ in
            bridge.handle(buffer: buffer)
        }
    }
}

@MainActor
final class SpeechFallbackASRRuntime: NSObject, ASRRuntimeProtocol {
    var onPartialTranscript: (@MainActor (String) -> Void)?
    var onFinalTranscript: (@MainActor (String) -> Void)?
    var onVoiceActivity: (@MainActor (Double) -> Void)?
    var onVoiceActivityStateChange: (@MainActor (VoiceActivityState) -> Void)?
    var onRuntimeReadinessChange: (@MainActor (SpeechRuntimeReadiness) -> Void)?

    private let audioRuntime: DuplexAudioRuntime
    private let audioEngine = AVAudioEngine()

    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var wantsListening = false
    private var configuredASRLocaleIdentifier = "en-US"
    private var voiceActivityState: VoiceActivityState = .silent
    private var readiness: SpeechRuntimeReadiness = .idle

    init(audioRuntime: DuplexAudioRuntime) {
        self.audioRuntime = audioRuntime
        super.init()
    }

    var hasActiveListeningIntent: Bool {
        wantsListening
    }

    func configureASR(localeIdentifier: String) {
        let trimmed = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "en-US" : trimmed
        guard configuredASRLocaleIdentifier != resolved else { return }
        configuredASRLocaleIdentifier = resolved
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: resolved))
    }

    func prepareASR(localeIdentifier: String) async throws {
        setReadiness(.preparing)
        configureASR(localeIdentifier: localeIdentifier)
        let capability = await evaluateSpeechCapability(requestPermissions: false)
        switch capability {
        case .ready:
            setReadiness(.ready)
        case .permissionsRequired, .permissionsDenied:
            setReadiness(.unavailable("Speech permissions are not available yet."))
        case .onDeviceUnsupported:
            setReadiness(.unavailable("On-device speech recognition is unavailable for this locale."))
        case .temporarilyUnavailable:
            setReadiness(.unavailable("Speech recognition is temporarily unavailable."))
        }
    }

    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus {
        let currentMicPermission = AVAudioApplication.shared.recordPermission
        let currentSpeechPermission = SFSpeechRecognizer.authorizationStatus()

        if requestPermissions, currentMicPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }

        let speechAuthorization: SFSpeechRecognizerAuthorizationStatus
        if requestPermissions, currentSpeechPermission == .notDetermined {
            speechAuthorization = await Self.requestSpeechAuthorization()
        } else {
            speechAuthorization = currentSpeechPermission
        }

        let resolvedMicPermission = AVAudioApplication.shared.recordPermission
        if resolvedMicPermission == .undetermined || speechAuthorization == .notDetermined {
            return .permissionsRequired
        }
        if resolvedMicPermission != .granted || speechAuthorization != .authorized {
            return .permissionsDenied
        }
        guard let speechRecognizer else {
            return .onDeviceUnsupported
        }
        guard speechRecognizer.supportsOnDeviceRecognition else {
            return .onDeviceUnsupported
        }
        guard speechRecognizer.isAvailable else {
            return .temporarilyUnavailable
        }
        return .ready
    }

    func startListening() async throws {
        wantsListening = true

        switch await evaluateSpeechCapability(requestPermissions: true) {
        case .ready:
            break
        case .permissionsRequired, .permissionsDenied:
            throw NSError(
                domain: "SpeechPipeline",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission was denied."]
            )
        case .onDeviceUnsupported:
            throw NSError(
                domain: "SpeechPipeline",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "This device does not support on-device English speech recognition."]
            )
        case .temporarilyUnavailable:
            throw NSError(
                domain: "SpeechPipeline",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition is currently unavailable."]
            )
        }

        guard let speechRecognizer else {
            throw NSError(
                domain: "SpeechPipeline",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "English on-device speech recognition is unavailable on this device."]
            )
        }

        try await audioRuntime.prepareAudioSessionForCall()
        teardownRecognition()
        setReadiness(.ready)
        updateVoiceActivityState(.listening)

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.addsPunctuation = true
        self.recognitionRequest = recognitionRequest

        let inputNode = audioEngine.inputNode
        audioRuntime.configureVoiceProcessingIfAvailable(for: inputNode)
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        let request = recognitionRequest
        let tapBridge = SpeechFallbackASRRealtimeBridge(
            request: request,
            publishVoiceLevel: Self.makeVoiceLevelPublisher(owner: self)
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format,
            block: SpeechFallbackASRRealtimeBridge.makeTapBlock(for: tapBridge)
        )

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeRecognitionHandler(owner: self)
        )
    }

    func stopListening() {
        wantsListening = false
        teardownRecognition()
        updateVoiceActivityState(.silent)
        onVoiceActivity?(0)
    }

    func suspendListening(reason: SpeechInterruptionReason) {
        guard wantsListening else { return }
        teardownRecognition()
        updateVoiceActivityState(.silent)
        onVoiceActivity?(0)
        if reason == .backgrounded {
            setReadiness(.idle)
        }
    }

    func recoverListeningIfNeeded() async throws {
        guard wantsListening else { return }
        try await startListening()
    }

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func teardownRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func restartListeningIfNeeded() async throws {
        guard wantsListening else { return }
        teardownRecognition()
        try await startListening()
    }

    private func updateVoiceActivityState(_ newValue: VoiceActivityState) {
        guard voiceActivityState != newValue else { return }
        voiceActivityState = newValue
        onVoiceActivityStateChange?(newValue)
    }

    private func setReadiness(_ newValue: SpeechRuntimeReadiness) {
        guard readiness != newValue else { return }
        readiness = newValue
        onRuntimeReadinessChange?(newValue)
    }

    nonisolated fileprivate static func computeLevel(for buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<count {
            sum += data[index] * data[index]
        }
        let rms = sqrt(sum / Float(count))
        return min(max(Double(rms * 10), 0), 1)
    }

    nonisolated private static func makeVoiceLevelPublisher(
        owner: SpeechFallbackASRRuntime
    ) -> @Sendable (Double) -> Void {
        { [weak owner] level in
            Task { @MainActor [weak owner] in
                guard let owner else { return }
                guard owner.wantsListening else { return }
                owner.onVoiceActivity?(level)
                owner.updateVoiceActivityState(level > 0.10 ? .userSpeaking : .listening)
            }
        }
    }

    nonisolated private static func makeRecognitionHandler(
        owner: SpeechFallbackASRRuntime
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorDomain = (error as NSError?)?.domain
            let errorCode = (error as NSError?)?.code
            Task { @MainActor [weak owner] in
                guard let owner else { return }

                if let transcript {
                    if isFinal {
                        owner.updateVoiceActivityState(owner.wantsListening ? .listening : .silent)
                        owner.onFinalTranscript?(transcript)
                    } else {
                        owner.updateVoiceActivityState(.userSpeaking)
                        owner.onPartialTranscript?(transcript)
                    }
                }

                if errorDomain != nil {
                    owner.recognitionRequest?.endAudio()
                    guard owner.wantsListening else { return }
                    guard errorDomain != "kAFAssistantErrorDomain" || errorCode != 216 else { return }
                    try? await owner.restartListeningIfNeeded()
                }
            }
        }
    }
}
