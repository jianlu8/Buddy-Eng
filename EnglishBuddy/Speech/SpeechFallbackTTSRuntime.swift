import AVFoundation
import Foundation

@MainActor
final class SpeechFallbackTTSRuntime: NSObject, TTSRuntimeProtocol {
    var onSpeechStateChange: (@MainActor (Bool) -> Void)?
    var onSpeechEnvelope: (@MainActor (Double) -> Void)?
    var onLipSyncFrame: (@MainActor (LipSyncFrame) -> Void)?

    private struct SpeechChunkPlayback {
        var chunk: SpeechChunk
        var estimatedDuration: TimeInterval
        var utteranceID: String
        var startedAt: Date?
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var configuredVoiceBundle = VoiceCatalog.defaultBundle(
        for: CharacterCatalog.flagship.id,
        languageID: LanguageCatalog.english.id
    )
    private var pendingPlaybacks: [SpeechChunkPlayback] = []
    private var currentPlayback: SpeechChunkPlayback?
    private var lipSyncTimer: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func configureTTS(voiceBundle: VoiceBundle) {
        configuredVoiceBundle = voiceBundle
    }

    func prepareTTS(voiceBundle: VoiceBundle) async throws {
        configureTTS(voiceBundle: voiceBundle)
    }

    func speak(chunks: [SpeechChunk], voiceStyle: VoiceStyle) async {
        let validChunks = chunks.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        guard validChunks.isEmpty == false else { return }

        for chunk in validChunks {
            let utterance = AVSpeechUtterance(string: chunk.text)
            utterance.rate = voiceStyle.rate
            utterance.pitchMultiplier = voiceStyle.pitchMultiplier
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = chunk.isFinal ? 0 : 0.02
            if let voiceIdentifier = voiceStyle.voiceIdentifier ?? configuredVoiceBundle.voiceIdentifier,
               let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: voiceStyle.languageCode)
            }
            let playback = SpeechChunkPlayback(
                chunk: chunk,
                estimatedDuration: Self.estimatedDuration(for: chunk.text, rate: voiceStyle.rate),
                utteranceID: utterance.speechString + "::" + chunk.id.uuidString
            )
            pendingPlaybacks.append(playback)
            synthesizer.speak(utterance)
        }
    }

    func interruptSpeech(reason: SpeechInterruptionReason) {
        stopSpeakingImmediately(notifyState: true)
    }

    func stopSpeakingImmediately(notifyState: Bool) {
        stopLipSync()
        pendingPlaybacks.removeAll()
        currentPlayback = nil
        synthesizer.stopSpeaking(at: .immediate)
        onSpeechEnvelope?(0)
        onLipSyncFrame?(LipSyncFrame.neutral)
        if notifyState {
            onSpeechStateChange?(false)
        }
    }

    private func startLipSync(for playback: SpeechChunkPlayback) {
        stopLipSync()
        currentPlayback = SpeechChunkPlayback(
            chunk: playback.chunk,
            estimatedDuration: playback.estimatedDuration,
            utteranceID: playback.utteranceID,
            startedAt: .now
        )
        onSpeechEnvelope?(0.08)
        onLipSyncFrame?(LipSyncFrame.neutral)
        lipSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickLipSync()
            }
        }
    }

    private func stopLipSync() {
        lipSyncTimer?.invalidate()
        lipSyncTimer = nil
        onSpeechEnvelope?(0)
        onLipSyncFrame?(LipSyncFrame.neutral)
    }

    private func tickLipSync() {
        guard let playback = currentPlayback, let startedAt = playback.startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let progress = min(max(elapsed / max(playback.estimatedDuration, 0.1), 0), 1)
        let frame = Self.makeLipSyncFrame(for: playback.chunk.text, progress: progress)
        onSpeechEnvelope?(max(0.04, frame.openness))
        onLipSyncFrame?(frame)
        if progress >= 1 {
            onSpeechEnvelope?(0.02)
        }
    }

    private static func estimatedDuration(for text: String, rate: Float) -> TimeInterval {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let tokenCount = max(tokens.count, 1)
        let normalizedRate = max(0.32, min(rate, 0.62))
        let secondsPerToken = max(0.14, 0.24 - Double(normalizedRate - 0.40) * 0.35)
        return max(0.45, Double(tokenCount) * secondsPerToken)
    }

    private static func makeLipSyncFrame(for text: String, progress: Double) -> LipSyncFrame {
        let scalars = Array(text.lowercased())
        guard scalars.isEmpty == false else { return .neutral }
        let index = min(max(Int(progress * Double(scalars.count - 1)), 0), scalars.count - 1)
        let character = scalars[index]
        let cadence = (sin(progress * .pi * 8) + 1) * 0.5

        let openness: Double
        let width: Double
        switch character {
        case "a", "e":
            openness = 0.78
            width = 0.42
        case "i", "y":
            openness = 0.48
            width = 0.70
        case "o":
            openness = 0.70
            width = 0.34
        case "u", "w":
            openness = 0.44
            width = 0.28
        case "m", "b", "p":
            openness = 0.10
            width = 0.18
        case "f", "v":
            openness = 0.24
            width = 0.46
        default:
            openness = 0.32 + cadence * 0.18
            width = 0.36 + cadence * 0.10
        }

        return LipSyncFrame(
            openness: openness,
            width: width,
            jawOffset: openness * 0.64,
            cheekLift: openness * 0.18,
            timestamp: .now
        )
    }
}

extension SpeechFallbackTTSRuntime: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let playback = self.pendingPlaybacks.isEmpty ? nil : self.pendingPlaybacks.removeFirst()
            if let playback {
                self.startLipSync(for: playback)
            }
            self.onSpeechStateChange?(true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentPlayback = nil
            self.stopLipSync()
            if self.synthesizer.isSpeaking == false, self.pendingPlaybacks.isEmpty {
                self.onSpeechStateChange?(false)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingPlaybacks.removeAll()
            self.currentPlayback = nil
            self.stopLipSync()
            self.onSpeechStateChange?(false)
        }
    }
}
