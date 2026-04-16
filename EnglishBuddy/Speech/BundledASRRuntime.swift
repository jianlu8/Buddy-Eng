import AVFoundation
import Foundation

private struct BundledASRRecognitionUpdate: Sendable {
    var text: String
    var endpointDetected: Bool
}

private enum BundledASRRecognitionEvent: Sendable {
    case update(BundledASRRecognitionUpdate)
    case failure(String)
}

private final class BundledASRWorker: @unchecked Sendable {
    private let bridge = SherpaOnnxASRBridge()
    private let queue = DispatchQueue(label: "com.hammond.EnglishBuddy.sherpa-asr", qos: .userInitiated)

    func prepare(assetURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.bridge.prepare(withAssetDirectoryURL: assetURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func processAudioSamples(
        _ data: Data,
        sampleRate: Int,
        inputFinished: Bool = false,
        completion: @escaping @Sendable (Result<BundledASRRecognitionUpdate, Error>) -> Void
    ) {
        queue.async {
            do {
                let result = try self.bridge.processAudioSamples(
                    data,
                    sampleRate: sampleRate,
                    inputFinished: inputFinished
                )
                let update = BundledASRRecognitionUpdate(
                    text: result.text,
                    endpointDetected: result.endpointDetected
                )
                completion(.success(update))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func reset() {
        queue.async {
            self.bridge.reset()
        }
    }
}

private final class BundledASRRealtimeBridge: @unchecked Sendable {
    typealias VoiceLevelPublisher = @Sendable (Double, Date) -> Void
    typealias RecognitionPublisher = @Sendable (BundledASRRecognitionEvent) -> Void

    private let worker: BundledASRWorker
    private let publishVoiceLevel: VoiceLevelPublisher
    private let publishRecognitionResult: RecognitionPublisher

    init(
        worker: BundledASRWorker,
        publishVoiceLevel: @escaping VoiceLevelPublisher,
        publishRecognitionResult: @escaping RecognitionPublisher
    ) {
        self.worker = worker
        self.publishVoiceLevel = publishVoiceLevel
        self.publishRecognitionResult = publishRecognitionResult
    }

    func handle(buffer: AVAudioPCMBuffer) {
        guard let floatSamples = BundledASRRuntime.makeFloatSamples(from: buffer), floatSamples.isEmpty == false else {
            return
        }

        let level = BundledASRRuntime.computeLevel(for: floatSamples)
        let now = Date()
        let sampleRate = Int(buffer.format.sampleRate.rounded())
        let data = floatSamples.withUnsafeBufferPointer { pointer in
            Data(buffer: pointer)
        }

        publishVoiceLevel(level, now)
        worker.processAudioSamples(data, sampleRate: sampleRate) { result in
            switch result {
            case .success(let update):
                self.publishRecognitionResult(.update(update))
            case .failure(let error):
                self.publishRecognitionResult(.failure(error.localizedDescription))
            }
        }
    }

    nonisolated static func makeTapBlock(for bridge: BundledASRRealtimeBridge) -> AVAudioNodeTapBlock {
        { buffer, _ in
            bridge.handle(buffer: buffer)
        }
    }
}

@MainActor
final class BundledASRRuntime: NSObject, ASRRuntimeProtocol {
    static let supportsTrueBundledExecution = true

    var onPartialTranscript: (@MainActor (String) -> Void)?
    var onFinalTranscript: (@MainActor (String) -> Void)?
    var onVoiceActivity: (@MainActor (Double) -> Void)?
    var onVoiceActivityStateChange: (@MainActor (VoiceActivityState) -> Void)?
    var onRuntimeReadinessChange: (@MainActor (SpeechRuntimeReadiness) -> Void)?

    private let descriptor: SpeechRuntimeDescriptor
    private let filesystem: AppFilesystem
    private let audioRuntime: DuplexAudioRuntime
    private let worker = BundledASRWorker()
    private let audioEngine = AVAudioEngine()

    private var readiness: SpeechRuntimeReadiness = .idle
    private var wantsListening = false
    private var configuredASRLocaleIdentifier = "en-US"
    private var voiceActivityState: VoiceActivityState = .silent
    private var lastPartialTranscript = ""
    private var lastFinalTranscript = ""
    private var preparedAssetURL: URL?
    private var smoothedVoiceLevel: Double = 0
    private var lastReportedVoiceLevel: Double = 0
    private var pendingSpeechStartedAt: Date?
    private var pendingSilenceStartedAt: Date?
    private var lastPartialEmissionAt: Date = .distantPast

    init(
        descriptor: SpeechRuntimeDescriptor,
        audioRuntime: DuplexAudioRuntime,
        filesystem: AppFilesystem = AppFilesystem()
    ) {
        self.descriptor = descriptor
        self.audioRuntime = audioRuntime
        self.filesystem = filesystem
        super.init()
    }

    var hasActiveListeningIntent: Bool {
        wantsListening
    }

    func configureASR(localeIdentifier: String) {
        let trimmed = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        configuredASRLocaleIdentifier = trimmed.isEmpty ? "en-US" : trimmed
    }

    func prepareASR(localeIdentifier: String) async throws {
        setReadiness(.preparing)
        configureASR(localeIdentifier: localeIdentifier)

        guard configuredASRLocaleIdentifier.lowercased().hasPrefix("en") else {
            let message = "Bundled ASR only supports English in this build."
            setReadiness(.unavailable(message))
            throw NSError(domain: "SpeechPipeline", code: 2205, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let assetURL = resolveAssetURL() else {
            let message = missingAssetMessage
            setReadiness(.unavailable(message))
            throw NSError(domain: "SpeechPipeline", code: 2201, userInfo: [NSLocalizedDescriptionKey: message])
        }

        do {
            try await worker.prepare(assetURL: assetURL)
            preparedAssetURL = assetURL
            lastPartialTranscript = ""
            lastFinalTranscript = ""
            smoothedVoiceLevel = 0
            lastReportedVoiceLevel = 0
            pendingSpeechStartedAt = nil
            pendingSilenceStartedAt = nil
            lastPartialEmissionAt = .distantPast
            setReadiness(.ready)
        } catch {
            preparedAssetURL = nil
            setReadiness(.unavailable(error.localizedDescription))
            throw error
        }
    }

    func evaluateSpeechCapability(requestPermissions: Bool) async -> SpeechCapabilityStatus {
        guard resolveAssetURL() != nil else {
            return .temporarilyUnavailable
        }

        let currentPermission = AVAudioApplication.shared.recordPermission
        if requestPermissions, currentPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .ready
        case .denied:
            return .permissionsDenied
        case .undetermined:
            return .permissionsRequired
        @unknown default:
            return .temporarilyUnavailable
        }
    }

    func startListening() async throws {
        wantsListening = true

        if preparedAssetURL == nil {
            try await prepareASR(localeIdentifier: configuredASRLocaleIdentifier)
        }

        switch await evaluateSpeechCapability(requestPermissions: true) {
        case .ready:
            break
        case .permissionsRequired, .permissionsDenied:
            wantsListening = false
            throw NSError(
                domain: "SpeechPipeline",
                code: 2206,
                userInfo: [NSLocalizedDescriptionKey: "Microphone access is required for bundled speech recognition."]
            )
        case .onDeviceUnsupported, .temporarilyUnavailable:
            wantsListening = false
            throw NSError(
                domain: "SpeechPipeline",
                code: 2207,
                userInfo: [NSLocalizedDescriptionKey: "Bundled speech recognition is unavailable right now."]
            )
        }

        try await audioRuntime.prepareAudioSessionForCall()
        teardownRecognition()
        worker.reset()
        lastPartialTranscript = ""
        lastFinalTranscript = ""
        smoothedVoiceLevel = 0
        lastReportedVoiceLevel = 0
        pendingSpeechStartedAt = nil
        pendingSilenceStartedAt = nil
        lastPartialEmissionAt = .distantPast
        setReadiness(.ready)
        updateVoiceActivityState(.listening)

        let inputNode = audioEngine.inputNode
        audioRuntime.configureVoiceProcessingIfAvailable(for: inputNode)
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        let tapBridge = BundledASRRealtimeBridge(
            worker: worker,
            publishVoiceLevel: Self.makeVoiceLevelPublisher(owner: self),
            publishRecognitionResult: Self.makeRecognitionPublisher(owner: self)
        )
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format,
            block: BundledASRRealtimeBridge.makeTapBlock(for: tapBridge)
        )

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopListening() {
        wantsListening = false
        teardownRecognition()
        worker.reset()
        lastPartialTranscript = ""
        lastFinalTranscript = ""
        smoothedVoiceLevel = 0
        lastReportedVoiceLevel = 0
        pendingSpeechStartedAt = nil
        pendingSilenceStartedAt = nil
        lastPartialEmissionAt = .distantPast
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

    private func handleCapturedVoiceLevel(_ level: Double, at now: Date) {
        smoothedVoiceLevel = (smoothedVoiceLevel * 0.68) + (level * 0.32)
        let quantizedLevel = Self.quantizedVoiceLevel(smoothedVoiceLevel)
        if abs(lastReportedVoiceLevel - quantizedLevel) >= 0.01 {
            lastReportedVoiceLevel = quantizedLevel
            onVoiceActivity?(quantizedLevel)
        }
        updateVoiceActivityState(using: quantizedLevel, at: now)
    }

    private func handleRecognitionResult(_ event: BundledASRRecognitionEvent) {
        switch event {
        case .update(let update):
            let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else {
                if update.endpointDetected {
                    lastPartialTranscript = ""
                    lastPartialEmissionAt = .distantPast
                    updateVoiceActivityState(wantsListening ? .listening : .silent)
                }
                return
            }

            if update.endpointDetected {
                lastPartialTranscript = ""
                lastPartialEmissionAt = .distantPast
                guard text != lastFinalTranscript else {
                    updateVoiceActivityState(wantsListening ? .listening : .silent)
                    return
                }
                lastFinalTranscript = text
                onFinalTranscript?(text)
                updateVoiceActivityState(wantsListening ? .listening : .silent)
            } else if shouldEmitPartial(text, at: .now) {
                lastPartialTranscript = text
                lastPartialEmissionAt = .now
                onPartialTranscript?(text)
            }
        case .failure(let message):
            setReadiness(.unavailable(message))
            teardownRecognition()
            wantsListening = false
            lastPartialTranscript = ""
            lastFinalTranscript = ""
            smoothedVoiceLevel = 0
            lastReportedVoiceLevel = 0
            pendingSpeechStartedAt = nil
            pendingSilenceStartedAt = nil
            lastPartialEmissionAt = .distantPast
            updateVoiceActivityState(.silent)
            onVoiceActivity?(0)
        }
    }

    private func resolveAssetURL() -> URL? {
        guard let assetID = descriptor.preferredAssetID else { return nil }
        return filesystem.embeddedSpeechAssetURL(for: assetID)
    }

    private var missingAssetMessage: String {
        let assetID = descriptor.preferredAssetID ?? "unknown-asr-asset"
        return "Bundled ASR asset \(assetID) is missing from the app package."
    }

    private func teardownRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func updateVoiceActivityState(_ newValue: VoiceActivityState) {
        guard voiceActivityState != newValue else { return }
        voiceActivityState = newValue
        onVoiceActivityStateChange?(newValue)
    }

    private func updateVoiceActivityState(using level: Double, at now: Date) {
        guard wantsListening else {
            pendingSpeechStartedAt = nil
            pendingSilenceStartedAt = nil
            updateVoiceActivityState(.silent)
            return
        }

        let speechThreshold = voiceActivityState == .userSpeaking ? 0.10 : 0.15
        let silenceThreshold = voiceActivityState == .userSpeaking ? 0.07 : 0.05

        if level >= speechThreshold {
            pendingSilenceStartedAt = nil
            pendingSpeechStartedAt = pendingSpeechStartedAt ?? now

            if now.timeIntervalSince(pendingSpeechStartedAt ?? now) >= 0.10 {
                updateVoiceActivityState(.userSpeaking)
            } else if voiceActivityState != .userSpeaking {
                updateVoiceActivityState(.listening)
            }
            return
        }

        pendingSpeechStartedAt = nil

        if level <= silenceThreshold {
            pendingSilenceStartedAt = pendingSilenceStartedAt ?? now
            if now.timeIntervalSince(pendingSilenceStartedAt ?? now) >= 0.18 {
                updateVoiceActivityState(.listening)
            }
            return
        }

        pendingSilenceStartedAt = nil
        if voiceActivityState != .userSpeaking {
            updateVoiceActivityState(.listening)
        }
    }

    private func shouldEmitPartial(_ text: String, at now: Date) -> Bool {
        guard text != lastPartialTranscript else { return false }

        let previousWordCount = lastPartialTranscript.split(whereSeparator: \.isWhitespace).count
        let currentWordCount = text.split(whereSeparator: \.isWhitespace).count
        let delta = abs(text.count - lastPartialTranscript.count)
        let endsAtBoundary = text.last.map { ".?!,\n".contains($0) } ?? false

        if endsAtBoundary || currentWordCount != previousWordCount || delta >= 6 {
            return true
        }

        return now.timeIntervalSince(lastPartialEmissionAt) >= 0.14
    }

    private func setReadiness(_ newValue: SpeechRuntimeReadiness) {
        guard readiness != newValue else { return }
        readiness = newValue
        onRuntimeReadinessChange?(newValue)
    }

    nonisolated fileprivate static func makeFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return nil }

        if let floatChannelData = buffer.floatChannelData {
            if channelCount == 1 {
                return Array(UnsafeBufferPointer(start: floatChannelData[0], count: frameCount))
            }

            var mono = [Float](repeating: 0, count: frameCount)
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: floatChannelData[channel], count: frameCount)
                for index in 0..<frameCount {
                    mono[index] += samples[index]
                }
            }
            let scale = 1.0 / Float(channelCount)
            for index in 0..<frameCount {
                mono[index] *= scale
            }
            return mono
        }

        if let int16ChannelData = buffer.int16ChannelData {
            var mono = [Float](repeating: 0, count: frameCount)
            for channel in 0..<channelCount {
                let samples = UnsafeBufferPointer(start: int16ChannelData[channel], count: frameCount)
                for index in 0..<frameCount {
                    mono[index] += Float(samples[index]) / Float(Int16.max)
                }
            }
            let scale = 1.0 / Float(channelCount)
            for index in 0..<frameCount {
                mono[index] *= scale
            }
            return mono
        }

        return nil
    }

    nonisolated fileprivate static func computeLevel(for samples: [Float]) -> Double {
        guard samples.isEmpty == false else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(samples.count))
        return min(max(Double(rms * 12), 0), 1)
    }

    nonisolated private static func quantizedVoiceLevel(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return (clamped * 50).rounded() / 50
    }

    nonisolated private static func makeVoiceLevelPublisher(
        owner: BundledASRRuntime
    ) -> @Sendable (Double, Date) -> Void {
        { [weak owner] level, now in
            Task { @MainActor [weak owner] in
                guard let owner else { return }
                guard owner.wantsListening else { return }
                owner.handleCapturedVoiceLevel(level, at: now)
            }
        }
    }

    nonisolated private static func makeRecognitionPublisher(
        owner: BundledASRRuntime
    ) -> @Sendable (BundledASRRecognitionEvent) -> Void {
        { [weak owner] event in
            Task { @MainActor [weak owner] in
                guard let owner else { return }
                guard owner.wantsListening else { return }
                owner.handleRecognitionResult(event)
            }
        }
    }
}
