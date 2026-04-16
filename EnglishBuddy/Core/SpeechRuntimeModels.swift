import Foundation

enum EnglishAccent: String, Codable, CaseIterable, Equatable, Sendable {
    case american
    case british

    var displayName: String {
        switch self {
        case .american:
            return "American English"
        case .british:
            return "British English"
        }
    }

    var shortLabel: String {
        switch self {
        case .american:
            return "American"
        case .british:
            return "British"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .american:
            return "en-US"
        case .british:
            return "en-GB"
        }
    }

    var pronunciationLexiconID: String {
        switch self {
        case .american:
            return "lexicon-us-en"
        case .british:
            return "lexicon-gb-en"
        }
    }
}

enum VoiceGenderPresentation: String, Codable, CaseIterable, Equatable, Sendable {
    case female
    case male

    var displayName: String {
        switch self {
        case .female:
            return "Female"
        case .male:
            return "Male"
        }
    }
}

enum TTSModelFamily: String, Codable, CaseIterable, Equatable, Sendable {
    case kokoro
    case piperLegacy = "piper-legacy"

    var runtimeID: String {
        switch self {
        case .kokoro:
            return "kokoro-tts"
        case .piperLegacy:
            return "piper-tts"
        }
    }

    var displayName: String {
        switch self {
        case .kokoro:
            return "Kokoro"
        case .piperLegacy:
            return "Piper Legacy"
        }
    }
}

enum SpeechProsodyPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case chatWarm
    case chatBright
    case tutorClearUS
    case tutorClearUK

    var defaultSilenceScale: Float {
        switch self {
        case .chatWarm:
            return 0.18
        case .chatBright:
            return 0.16
        case .tutorClearUS, .tutorClearUK:
            return 0.23
        }
    }

    var speedMultiplier: Float {
        switch self {
        case .chatWarm:
            return 1.0
        case .chatBright:
            return 1.04
        case .tutorClearUS, .tutorClearUK:
            return 0.92
        }
    }
}

enum SpeechRuntimeReadiness: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case unavailable(String)
}

enum SpeechAssetAvailability: String, Codable, Equatable, Sendable {
    case bundledReady
    case bundledMissing
    case fallbackOnly
}

struct SpeechRuntimeDescriptor: Codable, Equatable, Hashable, Sendable {
    var activeRuntimeID: String
    var preferredAssetID: String?
    var assetAvailability: SpeechAssetAvailability
    var fallbackReason: String?
}

struct SpeechRuntimeStatusSnapshot: Codable, Equatable, Hashable, Sendable {
    var asr: SpeechRuntimeDescriptor
    var tts: SpeechRuntimeDescriptor

    var usesFallbackRuntime: Bool {
        asr.activeRuntimeID.hasPrefix("system-") || tts.activeRuntimeID.hasPrefix("system-")
    }

    static let fallbackDefault = SpeechRuntimeStatusSnapshot(
        asr: SpeechRuntimeDescriptor(
            activeRuntimeID: "system-asr-fallback",
            preferredAssetID: nil,
            assetAvailability: .fallbackOnly,
            fallbackReason: "Bundled ASR runtime is not configured yet."
        ),
        tts: SpeechRuntimeDescriptor(
            activeRuntimeID: "system-tts-fallback",
            preferredAssetID: nil,
            assetAvailability: .fallbackOnly,
            fallbackReason: "Bundled TTS runtime is not configured yet."
        )
    )
}

struct SpeechRuntimeBuildFacts: Codable, Equatable, Hashable, Sendable {
    static let fileName = "RuntimeBuild.json"

    var sherpaOnnxEnabled: Bool
    var kokoroEnabled: Bool
    var piperEnabled: Bool
    var sherpaOnnxBridgeLinked: Bool
    var kokoroBridgeLinked: Bool
    var piperBridgeLinked: Bool
    var strictReleaseLane: Bool
    var allowsRuntimeFallback: Bool

    private enum CodingKeys: String, CodingKey {
        case sherpaOnnxEnabled
        case kokoroEnabled
        case piperEnabled
        case sherpaOnnxBridgeLinked
        case kokoroBridgeLinked
        case piperBridgeLinked
        case strictReleaseLane
        case allowsRuntimeFallback
    }

    init(
        sherpaOnnxEnabled: Bool,
        kokoroEnabled: Bool,
        piperEnabled: Bool,
        sherpaOnnxBridgeLinked: Bool,
        kokoroBridgeLinked: Bool,
        piperBridgeLinked: Bool,
        strictReleaseLane: Bool,
        allowsRuntimeFallback: Bool
    ) {
        self.sherpaOnnxEnabled = sherpaOnnxEnabled
        self.kokoroEnabled = kokoroEnabled
        self.piperEnabled = piperEnabled
        self.sherpaOnnxBridgeLinked = sherpaOnnxBridgeLinked
        self.kokoroBridgeLinked = kokoroBridgeLinked
        self.piperBridgeLinked = piperBridgeLinked
        self.strictReleaseLane = strictReleaseLane
        self.allowsRuntimeFallback = allowsRuntimeFallback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sherpaOnnxEnabled = try container.decodeIfPresent(Bool.self, forKey: .sherpaOnnxEnabled) ?? false
        let legacyPiperEnabled = try container.decodeIfPresent(Bool.self, forKey: .piperEnabled) ?? false
        kokoroEnabled = try container.decodeIfPresent(Bool.self, forKey: .kokoroEnabled) ?? legacyPiperEnabled
        piperEnabled = legacyPiperEnabled
        sherpaOnnxBridgeLinked = try container.decodeIfPresent(Bool.self, forKey: .sherpaOnnxBridgeLinked) ?? false
        let legacyPiperBridgeLinked = try container.decodeIfPresent(Bool.self, forKey: .piperBridgeLinked) ?? false
        kokoroBridgeLinked = try container.decodeIfPresent(Bool.self, forKey: .kokoroBridgeLinked) ?? legacyPiperBridgeLinked
        piperBridgeLinked = legacyPiperBridgeLinked
        strictReleaseLane = try container.decodeIfPresent(Bool.self, forKey: .strictReleaseLane) ?? false
        allowsRuntimeFallback = try container.decodeIfPresent(Bool.self, forKey: .allowsRuntimeFallback) ?? (strictReleaseLane == false)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sherpaOnnxEnabled, forKey: .sherpaOnnxEnabled)
        try container.encode(kokoroEnabled, forKey: .kokoroEnabled)
        try container.encode(piperEnabled, forKey: .piperEnabled)
        try container.encode(sherpaOnnxBridgeLinked, forKey: .sherpaOnnxBridgeLinked)
        try container.encode(kokoroBridgeLinked, forKey: .kokoroBridgeLinked)
        try container.encode(piperBridgeLinked, forKey: .piperBridgeLinked)
        try container.encode(strictReleaseLane, forKey: .strictReleaseLane)
        try container.encode(allowsRuntimeFallback, forKey: .allowsRuntimeFallback)
    }

    static func load(from directoryURL: URL?) -> SpeechRuntimeBuildFacts? {
        guard let directoryURL else { return nil }
        let factsURL = directoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: factsURL.path),
              let data = try? Data(contentsOf: factsURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(Self.self, from: data)
    }

    static func resolve(from directoryURL: URL?) -> SpeechRuntimeBuildFacts {
        let persisted = load(from: directoryURL)
        let manifest = BundledSpeechAssetManifest.load(from: directoryURL)

        let sherpaEnabled = SpeechRuntimeBuildFactResolver.booleanValue(
            environmentKeys: ["ENGLISHBUDDY_ENABLE_SHERPA_ONNX", "ENGLISHBUDDY_SPEECH_ENABLE_SHERPA_ONNX"],
            persistedValue: persisted?.sherpaOnnxEnabled,
            inferredValue: manifest?.assets.contains(where: { $0.runtimeID == "sherpa-onnx-asr" }) ?? false
        )
        let kokoroEnabled = SpeechRuntimeBuildFactResolver.booleanValue(
            environmentKeys: ["ENGLISHBUDDY_ENABLE_KOKORO", "ENGLISHBUDDY_SPEECH_ENABLE_KOKORO", "ENGLISHBUDDY_ENABLE_PIPER", "ENGLISHBUDDY_SPEECH_ENABLE_PIPER"],
            persistedValue: persisted?.kokoroEnabled,
            inferredValue: manifest?.assets.contains(where: { $0.runtimeID == "kokoro-tts" }) ?? false
        )
        let piperEnabled = SpeechRuntimeBuildFactResolver.booleanValue(
            environmentKeys: ["ENGLISHBUDDY_ENABLE_PIPER", "ENGLISHBUDDY_SPEECH_ENABLE_PIPER"],
            persistedValue: persisted?.piperEnabled,
            inferredValue: manifest?.assets.contains(where: { $0.runtimeID == "piper-tts" }) ?? false
        )
        let sherpaBridgeLinked = SpeechRuntimeBuildFactResolver.booleanValue(
            environmentKeys: ["ENGLISHBUDDY_LINK_SHERPA_ONNX", "ENGLISHBUDDY_SPEECH_BRIDGE_SHERPA_ONNX"],
            persistedValue: persisted?.sherpaOnnxBridgeLinked,
            inferredValue: false
        )
        let kokoroBridgeLinked = SpeechRuntimeBuildFactResolver.booleanValue(
            environmentKeys: ["ENGLISHBUDDY_LINK_KOKORO", "ENGLISHBUDDY_SPEECH_BRIDGE_KOKORO", "ENGLISHBUDDY_LINK_PIPER", "ENGLISHBUDDY_SPEECH_BRIDGE_PIPER"],
            persistedValue: persisted?.kokoroBridgeLinked,
            inferredValue: false
        )
        let piperBridgeLinked = SpeechRuntimeBuildFactResolver.booleanValue(
            environmentKeys: ["ENGLISHBUDDY_LINK_PIPER", "ENGLISHBUDDY_SPEECH_BRIDGE_PIPER"],
            persistedValue: persisted?.piperBridgeLinked,
            inferredValue: false
        )
        let strictReleaseLane = SpeechRuntimeBuildFactResolver.booleanValue(
            environmentKeys: ["ENGLISHBUDDY_RELEASE_LANE", "ENGLISHBUDDY_REQUIRE_BUNDLED_SPEECH"],
            persistedValue: persisted?.strictReleaseLane,
            inferredValue: false
        )
        let allowsRuntimeFallback = SpeechRuntimeBuildFactResolver.booleanValue(
            environmentKeys: ["ENGLISHBUDDY_ALLOW_SPEECH_FALLBACK_IN_RELEASE"],
            persistedValue: persisted?.allowsRuntimeFallback,
            inferredValue: strictReleaseLane == false
        )

        return SpeechRuntimeBuildFacts(
            sherpaOnnxEnabled: sherpaEnabled,
            kokoroEnabled: kokoroEnabled,
            piperEnabled: piperEnabled,
            sherpaOnnxBridgeLinked: sherpaBridgeLinked,
            kokoroBridgeLinked: kokoroBridgeLinked,
            piperBridgeLinked: piperBridgeLinked,
            strictReleaseLane: strictReleaseLane,
            allowsRuntimeFallback: allowsRuntimeFallback
        )
    }
}

struct SpeechRuntimeIntegrationAvailability: Codable, Equatable, Hashable, Sendable {
    var sherpaOnnxEnabled: Bool
    var kokoroEnabled: Bool
    var piperEnabled: Bool

    static var current: SpeechRuntimeIntegrationAvailability {
        resolve(
            from: Bundle.main.resourceURL?.appendingPathComponent("SpeechAssets", isDirectory: true)
        )
    }

    static func resolve(from directoryURL: URL?) -> SpeechRuntimeIntegrationAvailability {
        let facts = SpeechRuntimeBuildFacts.resolve(from: directoryURL)
        return SpeechRuntimeIntegrationAvailability(
            sherpaOnnxEnabled: facts.sherpaOnnxEnabled,
            kokoroEnabled: facts.kokoroEnabled,
            piperEnabled: facts.piperEnabled
        )
    }
}

private enum SpeechRuntimeBuildFactResolver {
    static func booleanValue(
        environmentKeys: [String],
        persistedValue: Bool?,
        inferredValue: Bool
    ) -> Bool {
        if let envValue = environmentBoolean(for: environmentKeys) {
            return envValue
        }
        if let persistedValue {
            return persistedValue
        }
        return inferredValue
    }

    private static func environmentBoolean(for keys: [String]) -> Bool? {
        let environment = ProcessInfo.processInfo.environment
        for key in keys {
            guard let rawValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  rawValue.isEmpty == false else {
                continue
            }

            switch rawValue.lowercased() {
            case "1", "true", "yes", "y", "on":
                return true
            case "0", "false", "no", "n", "off":
                return false
            default:
                continue
            }
        }
        return nil
    }
}

enum VoiceActivityState: String, Codable, Equatable, Sendable {
    case silent
    case listening
    case userSpeaking
}

enum SpeechInterruptionReason: String, Codable, Equatable, Sendable {
    case bargeIn
    case userRequested
    case systemInterruption
    case routeChange
    case backgrounded
    case sessionEnded
    case runtimeReset
}

enum VoiceEmotionPreset: String, Codable, CaseIterable, Equatable, Sendable {
    case neutral
    case warm
    case tutorFocused
    case animated
}

enum SpeechChunkingPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case sentence
    case phrase
    case adaptive
}

enum CharacterReleaseTier: String, Codable, CaseIterable, Equatable, Sendable {
    case flagship
    case future
}

struct SpeechChunk: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var text: String
    var isFinal: Bool

    init(id: UUID = UUID(), text: String, isFinal: Bool = true) {
        self.id = id
        self.text = text
        self.isFinal = isFinal
    }
}

struct LipSyncFrame: Codable, Equatable, Hashable, Sendable {
    var openness: Double
    var width: Double
    var jawOffset: Double
    var cheekLift: Double
    var timestamp: Date

    static var neutral: LipSyncFrame {
        LipSyncFrame(
            openness: 0,
            width: 0,
            jawOffset: 0,
            cheekLift: 0,
            timestamp: .now
        )
    }
}

struct SpeechInterruptionSnapshot: Codable, Equatable, Sendable {
    var reason: SpeechInterruptionReason
    var assistantText: String
    var userText: String
    var happenedAt: Date
}

struct SpeechTurnMetrics: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var sessionID: UUID?
    var callToFirstCaptionMs: Int?
    var speechToFirstPartialMs: Int?
    var captionToSpeechStartMs: Int?
    var bargeInToStopMs: Int?
    var subtitleDragResponseMs: Int?
    var keyboardOpenLatencyMs: Int?
    var lipSyncDelayMs: Int?
    var measuredAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        callToFirstCaptionMs: Int? = nil,
        speechToFirstPartialMs: Int? = nil,
        captionToSpeechStartMs: Int? = nil,
        bargeInToStopMs: Int? = nil,
        subtitleDragResponseMs: Int? = nil,
        keyboardOpenLatencyMs: Int? = nil,
        lipSyncDelayMs: Int? = nil,
        measuredAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.callToFirstCaptionMs = callToFirstCaptionMs
        self.speechToFirstPartialMs = speechToFirstPartialMs
        self.captionToSpeechStartMs = captionToSpeechStartMs
        self.bargeInToStopMs = bargeInToStopMs
        self.subtitleDragResponseMs = subtitleDragResponseMs
        self.keyboardOpenLatencyMs = keyboardOpenLatencyMs
        self.lipSyncDelayMs = lipSyncDelayMs
        self.measuredAt = measuredAt
    }
}

@MainActor
final class CallPerformanceTracer {
    private let clock = ContinuousClock()
    private var activeSessionID: UUID?
    private var callStartedAt: ContinuousClock.Instant?
    private var userSpeechStartedAt: ContinuousClock.Instant?
    private var firstCaptionAt: ContinuousClock.Instant?
    private var speechStartedAt: ContinuousClock.Instant?
    private var bargeInStartedAt: ContinuousClock.Instant?
    private var didCaptureLipSyncDelay = false
    private var latestMetrics = SpeechTurnMetrics()

    func begin(sessionID: UUID) {
        activeSessionID = sessionID
        callStartedAt = clock.now
        userSpeechStartedAt = nil
        firstCaptionAt = nil
        speechStartedAt = nil
        bargeInStartedAt = nil
        didCaptureLipSyncDelay = false
        latestMetrics = SpeechTurnMetrics(sessionID: sessionID)
    }

    func markFirstAssistantCaptionIfNeeded() {
        guard firstCaptionAt == nil else { return }
        guard let callStartedAt else { return }
        let now = clock.now
        firstCaptionAt = now
        latestMetrics.callToFirstCaptionMs = elapsedMilliseconds(from: callStartedAt, to: now)
    }

    func markUserSpeechStartIfNeeded() {
        guard userSpeechStartedAt == nil else { return }
        userSpeechStartedAt = clock.now
    }

    func markFirstPartialTranscriptIfNeeded(_ transcript: String) {
        guard latestMetrics.speechToFirstPartialMs == nil else { return }
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        guard let userSpeechStartedAt else { return }
        latestMetrics.speechToFirstPartialMs = elapsedMilliseconds(from: userSpeechStartedAt, to: clock.now)
    }

    func markAssistantSpeechStartIfNeeded() {
        guard speechStartedAt == nil else { return }
        let now = clock.now
        speechStartedAt = now
        if let firstCaptionAt {
            latestMetrics.captionToSpeechStartMs = elapsedMilliseconds(from: firstCaptionAt, to: now)
        }
    }

    func markFirstLipSyncFrameIfNeeded(_ frame: LipSyncFrame) {
        guard didCaptureLipSyncDelay == false else { return }
        guard max(frame.openness, frame.width, frame.jawOffset, frame.cheekLift) > 0.01 else { return }
        guard let speechStartedAt else { return }
        didCaptureLipSyncDelay = true
        latestMetrics.lipSyncDelayMs = elapsedMilliseconds(from: speechStartedAt, to: clock.now)
    }

    func markBargeInRequested() {
        bargeInStartedAt = clock.now
    }

    func markBargeInStopped() {
        guard let bargeInStartedAt else { return }
        latestMetrics.bargeInToStopMs = elapsedMilliseconds(from: bargeInStartedAt, to: clock.now)
        self.bargeInStartedAt = nil
    }

    func recordSubtitleDragResponse(milliseconds: Int) {
        latestMetrics.subtitleDragResponseMs = milliseconds
    }

    func recordKeyboardOpenLatency(milliseconds: Int) {
        latestMetrics.keyboardOpenLatencyMs = milliseconds
    }

    func finalize() -> [SpeechTurnMetrics] {
        guard activeSessionID != nil else { return [] }
        latestMetrics.measuredAt = .now
        return [latestMetrics]
    }

    private func elapsedMilliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Int {
        max(0, Int(start.duration(to: end).components.seconds * 1_000) + Int(start.duration(to: end).components.attoseconds / 1_000_000_000_000_000))
    }
}
