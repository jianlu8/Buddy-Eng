import AVFoundation
import Speech
import UIKit

@MainActor
final class LiveSpeechPipeline: NSObject, SpeechPipelineProtocol {
    var onPartialTranscript: (@MainActor (String) -> Void)?
    var onFinalTranscript: (@MainActor (String) -> Void)?
    var onVoiceActivity: (@MainActor (Double) -> Void)?
    var onSpeechStateChange: (@MainActor (Bool) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var wantsListening = false

    override init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruptionNotification(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChangeNotification), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackgroundNotification), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForegroundNotification), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
            throw NSError(domain: "SpeechPipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission was denied."])
        case .onDeviceUnsupported:
            throw NSError(domain: "SpeechPipeline", code: 5, userInfo: [NSLocalizedDescriptionKey: "This device does not support on-device English speech recognition."])
        case .temporarilyUnavailable:
            throw NSError(domain: "SpeechPipeline", code: 4, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is currently unavailable."])
        }

        guard let speechRecognizer else {
            throw NSError(domain: "SpeechPipeline", code: 3, userInfo: [NSLocalizedDescriptionKey: "English on-device speech recognition is unavailable on this device."])
        }

        try configureAudioSession()
        teardownRecognition()

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.addsPunctuation = true
        self.recognitionRequest = recognitionRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format,
            block: Self.makeRecognitionTap(
                request: recognitionRequest,
                onVoiceActivity: onVoiceActivity
            )
        )

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    let transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.onFinalTranscript?(transcript)
                    } else {
                        self.onPartialTranscript?(transcript)
                    }
                }
            }

            if let error {
                Task { @MainActor in
                    self.recognitionRequest?.endAudio()
                    let nsError = error as NSError
                    guard self.wantsListening else { return }
                    guard nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 else { return }
                    try? await self.restartListeningIfNeeded()
                }
            }
        }
    }

    func stopListening() {
        wantsListening = false
        teardownRecognition()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        onVoiceActivity?(0)
    }

    func speak(text: String, voiceStyle: VoiceStyle) async {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = voiceStyle.rate
        utterance.pitchMultiplier = voiceStyle.pitchMultiplier
        utterance.voice = AVSpeechSynthesisVoice(language: voiceStyle.languageCode)
        synthesizer.speak(utterance)
    }

    func interruptSpeech() {
        synthesizer.stopSpeaking(at: .immediate)
        onSpeechStateChange?(false)
    }

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated private static func makeRecognitionTap(
        request: SFSpeechAudioBufferRecognitionRequest,
        onVoiceActivity: (@MainActor (Double) -> Void)?
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            guard buffer.frameLength > 0, audioBuffer.mDataByteSize > 0 else { return }
            request.append(buffer)

            guard let onVoiceActivity else { return }
            let level = Self.computeLevel(for: buffer)
            Task { @MainActor in
                onVoiceActivity(level)
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
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

    @objc nonisolated private func handleAudioInterruptionNotification(_ notification: Notification) {
        let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        Task { @MainActor [weak self] in
            self?.handleAudioInterruption(typeRawValue: rawValue)
        }
    }

    @objc nonisolated private func handleRouteChangeNotification() {
        Task { @MainActor [weak self] in
            self?.handleRouteChange()
        }
    }

    @objc nonisolated private func handleDidEnterBackgroundNotification() {
        Task { @MainActor [weak self] in
            self?.handleDidEnterBackground()
        }
    }

    @objc nonisolated private func handleWillEnterForegroundNotification() {
        Task { @MainActor [weak self] in
            self?.handleWillEnterForeground()
        }
    }

    private func handleAudioInterruption(typeRawValue: UInt?) {
        guard let rawValue = typeRawValue,
              let type = AVAudioSession.InterruptionType(rawValue: rawValue) else {
            return
        }

        switch type {
        case .began:
            teardownRecognition()
            onVoiceActivity?(0)
        case .ended:
            guard wantsListening else { return }
            Task { @MainActor in
                try? await restartListeningIfNeeded()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange() {
        guard wantsListening else { return }
        Task { @MainActor in
            try? configureAudioSession()
        }
    }

    private func handleDidEnterBackground() {
        guard wantsListening else { return }
        teardownRecognition()
    }

    private func handleWillEnterForeground() {
        guard wantsListening else { return }
        Task { @MainActor in
            try? await restartListeningIfNeeded()
        }
    }

    nonisolated private static func computeLevel(for buffer: AVAudioPCMBuffer) -> Double {
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
}

extension LiveSpeechPipeline: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.onSpeechStateChange?(true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.onSpeechStateChange?(false)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.onSpeechStateChange?(false)
        }
    }
}
