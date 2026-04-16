import AVFoundation
import Foundation

private struct BundledTTSClip: Sendable {
    var pcmFloatData: Data
    var sampleRate: Int
    var sampleCount: Int
    var text: String
}

private struct BundledTTSPreparation: Sendable {
    var assetURL: URL
    var lexiconPath: String?
    var languageHint: String?

    var cacheKey: String {
        [assetURL.path, lexiconPath ?? "", languageHint ?? ""].joined(separator: "|")
    }
}

private struct BundledTTSSynthesisOptions: Sendable {
    var speakerID: Int
    var speed: Float
    var silenceScale: Float
    var extraJSON: String?
}

private final class BundledTTSWorker: @unchecked Sendable {
    private let bridge = SherpaOnnxTTSBridge()
    private let queue = DispatchQueue(label: "com.hammond.EnglishBuddy.sherpa-tts", qos: .userInitiated)

    func prepare(_ preparation: BundledTTSPreparation) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.bridge.prepare(
                        withAssetDirectoryURL: preparation.assetURL,
                        lexiconPath: preparation.lexiconPath,
                        languageHint: preparation.languageHint
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func generateClip(text: String, options: BundledTTSSynthesisOptions) async throws -> BundledTTSClip {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BundledTTSClip, Error>) in
            queue.async {
                do {
                    let result = try self.bridge.generateSpeech(
                        forText: text,
                        speakerID: options.speakerID,
                        speed: options.speed,
                        silenceScale: options.silenceScale,
                        extraJSON: options.extraJSON
                    )
                    continuation.resume(returning: BundledTTSClip(
                        pcmFloatData: result.pcmFloatData,
                        sampleRate: result.sampleRate,
                        sampleCount: result.sampleCount,
                        text: text
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
final class BundledTTSRuntime: TTSRuntimeProtocol {
    static let supportsTrueBundledExecution = true

    var onSpeechStateChange: (@MainActor (Bool) -> Void)?
    var onSpeechEnvelope: (@MainActor (Double) -> Void)?
    var onLipSyncFrame: (@MainActor (LipSyncFrame) -> Void)?

    private let descriptor: SpeechRuntimeDescriptor
    private let filesystem: AppFilesystem
    private let worker = BundledTTSWorker()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private var configuredVoiceBundle = VoiceCatalog.defaultBundle(
        for: CharacterCatalog.flagship.id,
        languageID: LanguageCatalog.english.id
    )
    private var pendingChunks: [SpeechChunk] = []
    private var isProcessingQueue = false
    private var preparedConfigurationKey: String?
    private var activeGenerationID = UUID()
    private var lipSyncTimer: Timer?
    private var currentLipSyncFrames: [LipSyncFrame] = []
    private var currentLipSyncIndex = 0
    private var currentFormatKey: String?
    private var activePlaybackContinuation: CheckedContinuation<Void, Error>?

    init(
        descriptor: SpeechRuntimeDescriptor,
        filesystem: AppFilesystem = AppFilesystem()
    ) {
        self.descriptor = descriptor
        self.filesystem = filesystem
        audioEngine.attach(playerNode)
    }

    func configureTTS(voiceBundle: VoiceBundle) {
        configuredVoiceBundle = voiceBundle
    }

    func prepareTTS(voiceBundle: VoiceBundle) async throws {
        configureTTS(voiceBundle: voiceBundle)
        guard let preparation = resolvePreparation() else {
            throw NSError(domain: "SpeechPipeline", code: 2301, userInfo: [NSLocalizedDescriptionKey: missingAssetMessage])
        }
        try await worker.prepare(preparation)
        preparedConfigurationKey = preparation.cacheKey
    }

    func speak(chunks: [SpeechChunk], voiceStyle: VoiceStyle) async {
        let validChunks = chunks.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        guard validChunks.isEmpty == false else { return }
        guard resolveAssetURL() != nil else {
            onSpeechStateChange?(false)
            onSpeechEnvelope?(0)
            onLipSyncFrame?(.neutral)
            return
        }

        enqueue(chunks: validChunks)
        guard isProcessingQueue == false else { return }
        isProcessingQueue = true
        let generationID = activeGenerationID
        await processQueue(generationID: generationID, voiceStyle: voiceStyle)
    }

    func interruptSpeech(reason: SpeechInterruptionReason) {
        activeGenerationID = UUID()
        pendingChunks.removeAll(keepingCapacity: true)
        isProcessingQueue = false
        if let activePlaybackContinuation {
            self.activePlaybackContinuation = nil
            activePlaybackContinuation.resume()
        }
        stopLipSync()
        if playerNode.isPlaying {
            playerNode.stop()
        }
        playerNode.reset()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        currentFormatKey = nil
        onSpeechEnvelope?(0)
        onLipSyncFrame?(.neutral)
        onSpeechStateChange?(false)
    }

    private func processQueue(generationID: UUID, voiceStyle: VoiceStyle) async {
        defer {
            if activeGenerationID == generationID {
                isProcessingQueue = false
            }
        }

        while activeGenerationID == generationID, pendingChunks.isEmpty == false {
            let chunk = pendingChunks.removeFirst()
            let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { continue }

            do {
                if let preparation = resolvePreparation(),
                   preparedConfigurationKey != preparation.cacheKey {
                    try await worker.prepare(preparation)
                    preparedConfigurationKey = preparation.cacheKey
                }

                let clip = try await worker.generateClip(
                    text: text,
                    options: synthesisOptions(for: text, voiceStyle: voiceStyle)
                )
                guard activeGenerationID == generationID else { return }
                try await playClip(clip, generationID: generationID)
            } catch {
                guard activeGenerationID == generationID else { return }
                pendingChunks.removeAll()
                stopLipSync()
                onSpeechEnvelope?(0)
                onLipSyncFrame?(.neutral)
                onSpeechStateChange?(false)
                return
            }
        }

        guard activeGenerationID == generationID else { return }
        stopLipSync()
        onSpeechEnvelope?(0)
        onLipSyncFrame?(.neutral)
        onSpeechStateChange?(false)
    }

    private func playClip(_ clip: BundledTTSClip, generationID: UUID) async throws {
        guard clip.sampleCount > 0 else { return }
        let buffer = try makePCMBuffer(from: clip)
        try ensurePlaybackEngine(for: buffer.format)

        if playerNode.isPlaying == false {
            playerNode.play()
        }

        let lipSyncFrames = Self.makeLipSyncFrames(
            from: clip.pcmFloatData,
            sampleRate: clip.sampleRate,
            text: clip.text
        )
        startLipSync(frames: lipSyncFrames)
        onSpeechStateChange?(true)

        try await withCheckedThrowingContinuation { continuation in
            activePlaybackContinuation = continuation
            playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard let playbackContinuation = self.activePlaybackContinuation else { return }
                    self.activePlaybackContinuation = nil
                    guard self.activeGenerationID == generationID else {
                        playbackContinuation.resume()
                        return
                    }
                    self.stopLipSyncIfIdle()
                    playbackContinuation.resume()
                }
            }
        }
    }

    private func ensurePlaybackEngine(for format: AVAudioFormat) throws {
        let formatKey = "\(Int(format.sampleRate.rounded()))-\(format.channelCount)"
        if currentFormatKey != formatKey {
            audioEngine.stop()
            audioEngine.disconnectNodeOutput(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            currentFormatKey = formatKey
        }

        if audioEngine.isRunning == false {
            audioEngine.prepare()
            try audioEngine.start()
        }
    }

    private func makePCMBuffer(from clip: BundledTTSClip) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(clip.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "SpeechPipeline",
                code: 2305,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create the audio format for bundled TTS output."]
            )
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(clip.sampleCount)
        ) else {
            throw NSError(
                domain: "SpeechPipeline",
                code: 2306,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate the audio buffer for bundled TTS output."]
            )
        }

        buffer.frameLength = AVAudioFrameCount(clip.sampleCount)
        clip.pcmFloatData.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: Float.self).baseAddress,
                  let destination = buffer.floatChannelData?[0] else {
                return
            }
            destination.update(from: source, count: clip.sampleCount)
        }
        return buffer
    }

    private func startLipSync(frames: [LipSyncFrame]) {
        stopLipSync()
        currentLipSyncFrames = frames
        currentLipSyncIndex = 0
        guard frames.isEmpty == false else {
            onSpeechEnvelope?(0.06)
            onLipSyncFrame?(.neutral)
            return
        }

        let initial = frames[0]
        onSpeechEnvelope?(max(0.04, initial.openness))
        onLipSyncFrame?(initial)
        lipSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickLipSync()
            }
        }
    }

    private func stopLipSyncIfIdle() {
        guard pendingChunks.isEmpty else { return }
        stopLipSync()
    }

    private func stopLipSync() {
        lipSyncTimer?.invalidate()
        lipSyncTimer = nil
        currentLipSyncFrames.removeAll()
        currentLipSyncIndex = 0
    }

    private func enqueue(chunks: [SpeechChunk]) {
        for chunk in chunks {
            let trimmed = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }

            if var last = pendingChunks.last, shouldCoalesce(last, with: chunk) {
                last.text = last.text.trimmingCharacters(in: .whitespacesAndNewlines) + " " + trimmed
                last.isFinal = chunk.isFinal
                pendingChunks[pendingChunks.count - 1] = last
            } else {
                pendingChunks.append(SpeechChunk(id: chunk.id, text: trimmed, isFinal: chunk.isFinal))
            }
        }
    }

    private func shouldCoalesce(_ previous: SpeechChunk, with current: SpeechChunk) -> Bool {
        if previous.isFinal {
            return false
        }

        let previousText = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentText = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard previousText.isEmpty == false, currentText.isEmpty == false else { return false }
        guard previousText.count <= 28 || currentText.count <= 22 else { return false }

        let previousEndsSentence = previousText.last.map { ".?!".contains($0) } ?? false
        return previousEndsSentence == false
    }

    private func tickLipSync() {
        guard currentLipSyncFrames.isEmpty == false else {
            onSpeechEnvelope?(0)
            onLipSyncFrame?(.neutral)
            return
        }

        let frame = currentLipSyncFrames[min(currentLipSyncIndex, currentLipSyncFrames.count - 1)]
        onSpeechEnvelope?(max(0.02, frame.openness))
        onLipSyncFrame?(frame)
        currentLipSyncIndex += 1

        if currentLipSyncIndex >= currentLipSyncFrames.count {
            onSpeechEnvelope?(0.02)
        }
    }

    private func resolveAssetURL() -> URL? {
        guard let assetID = descriptor.preferredAssetID else { return nil }
        return filesystem.embeddedSpeechAssetURL(for: assetID)
    }

    private func resolvePreparation() -> BundledTTSPreparation? {
        guard let assetURL = resolveAssetURL() else { return nil }
        return BundledTTSPreparation(
            assetURL: assetURL,
            lexiconPath: resolveLexiconPath(assetURL: assetURL),
            languageHint: configuredVoiceBundle.accent.localeIdentifier.lowercased()
        )
    }

    private var missingAssetMessage: String {
        let assetID = descriptor.preferredAssetID ?? "unknown-tts-asset"
        return "Bundled TTS asset \(assetID) is missing from the app package."
    }

    private func speedScalar(for voiceStyle: VoiceStyle, voiceBundle: VoiceBundle) -> Float {
        let normalizedRate = max(0.35, min(voiceStyle.rate, 0.62))
        let rateScalar = Double(normalizedRate / 0.47)
        let bundleScalar = Double(max(0.9, min(voiceBundle.rateMultiplier, 1.1)))
        let prosodyScalar = Double(voiceStyle.prosodyPolicy.speedMultiplier)
        return Float(max(0.78, min(rateScalar * bundleScalar * prosodyScalar, 1.18)))
    }

    private func synthesisOptions(for text: String, voiceStyle: VoiceStyle) -> BundledTTSSynthesisOptions {
        BundledTTSSynthesisOptions(
            speakerID: max(0, configuredVoiceBundle.runtimeSpeakerID),
            speed: speedScalar(for: voiceStyle, voiceBundle: configuredVoiceBundle),
            silenceScale: silenceScale(for: text, policy: voiceStyle.prosodyPolicy),
            extraJSON: nil
        )
    }

    private func silenceScale(for text: String, policy: SpeechProsodyPolicy) -> Float {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var silenceScale = policy.defaultSilenceScale

        if trimmed.contains("?") {
            silenceScale += 0.03
        }
        if trimmed.contains(":") || trimmed.contains(";") {
            silenceScale += 0.02
        }
        if trimmed.contains(",") {
            silenceScale += 0.01
        }

        return min(max(silenceScale, 0.08), 0.30)
    }

    private func resolveLexiconPath(assetURL: URL) -> String? {
        let fileName: String
        switch configuredVoiceBundle.pronunciationLexiconID {
        case EnglishAccent.british.pronunciationLexiconID:
            fileName = "lexicon-gb-en.txt"
        default:
            fileName = "lexicon-us-en.txt"
        }

        let lexiconURL = assetURL.appendingPathComponent(fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: lexiconURL.path) else { return nil }
        return lexiconURL.path
    }

    nonisolated private static func makeLipSyncFrames(
        from pcmFloatData: Data,
        sampleRate: Int,
        text: String
    ) -> [LipSyncFrame] {
        let samples = pcmFloatData.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
        guard samples.isEmpty == false, sampleRate > 0 else { return [] }

        let targetFramesPerSecond = 24
        let windowSize = max(1, sampleRate / targetFramesPerSecond)
        var frames: [LipSyncFrame] = []
        frames.reserveCapacity(max(1, samples.count / windowSize))

        let characters = Array(text.lowercased())
        for offset in stride(from: 0, to: samples.count, by: windowSize) {
            let end = min(offset + windowSize, samples.count)
            let window = samples[offset..<end]
            let rms = sqrt(window.reduce(0) { partial, sample in
                partial + (sample * sample)
            } / Float(max(window.count, 1)))

            let progress = Double(offset) / Double(max(samples.count - 1, 1))
            let character = characters.isEmpty ? " " : characters[min(Int(progress * Double(characters.count - 1)), characters.count - 1)]
            let baseWidth: Double
            switch character {
            case "i", "y":
                baseWidth = 0.72
            case "o", "u", "w":
                baseWidth = 0.30
            case "m", "b", "p":
                baseWidth = 0.18
            default:
                baseWidth = 0.44
            }

            let openness = min(max(Double(rms) * 10.5, 0.04), 0.92)
            frames.append(
                LipSyncFrame(
                    openness: openness,
                    width: baseWidth,
                    jawOffset: openness * 0.62,
                    cheekLift: openness * 0.16,
                    timestamp: .now
                )
            )
        }

        return frames
    }
}
