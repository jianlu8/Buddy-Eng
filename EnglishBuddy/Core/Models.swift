import Foundation

enum ConversationMode: String, Codable, CaseIterable, Identifiable {
    case chat
    case tutor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "Chat"
        case .tutor:
            return "Tutor"
        }
    }

    var subtitle: String {
        switch self {
        case .chat:
            return "Companion-style practice with lighter corrections"
        case .tutor:
            return "Goal-driven coaching with sharper feedback"
        }
    }
}

enum InferenceBackendPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case gpu
    case cpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpu:
            return "GPU"
        case .cpu:
            return "CPU"
        }
    }
}

enum AvatarState: String, Codable, Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case interrupted
    case error
}

enum TurnRole: String, Codable {
    case user
    case assistant
    case system
}

enum FeedbackCategory: String, Codable {
    case grammar
    case vocabulary
    case pronunciation
}

enum ModelInstallStatus: String, Codable {
    case notInstalled
    case downloading
    case installed
    case corrupted
    case failed
}

enum CEFRLevel: String, Codable, CaseIterable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
}

enum VocabularyMastery: String, Codable {
    case new
    case practicing
    case confident
}

enum SubtitleSpeaker: String, Codable {
    case user
    case assistant
    case system
}

enum SubtitleOverlayMode: String, Codable {
    case collapsed
    case expanded
    case fullTranscript
}

enum SpeechCapabilityStatus: String, Codable, Equatable, Hashable {
    case ready
    case permissionsRequired
    case permissionsDenied
    case onDeviceUnsupported
    case temporarilyUnavailable
}

enum CallInputMode: String, Codable, Equatable, Hashable {
    case liveVoice
    case textAssisted
}

enum CallReadinessDisposition: String, Codable, Equatable, Hashable {
    case liveVoice
    case textAssisted
    case fatal
}

enum CharacterSurfaceKind: String, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case homeHero
    case quickStartPreview
    case callHero
    case historyPreview
    case feedbackHero
    case settingsPreview

    var id: String { rawValue }
}

enum ScenarioCategory: String, Codable, CaseIterable, Identifiable {
    case freeTalk
    case lectureStyleExplanation
    case roleplayPractice
    case gameThemeChallenge
    case pronunciationDrill
    case vocabularyCarryOver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeTalk:
            return "Free Talk"
        case .lectureStyleExplanation:
            return "Lecture Style"
        case .roleplayPractice:
            return "Roleplay"
        case .gameThemeChallenge:
            return "Theme Challenge"
        case .pronunciationDrill:
            return "Pronunciation Drill"
        case .vocabularyCarryOver:
            return "Vocabulary Carry-over"
        }
    }
}

enum PerformanceTier: String, Codable, CaseIterable, Identifiable {
    case balanced
    case efficiency
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .efficiency:
            return "Efficiency"
        case .quality:
            return "Quality"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced:
            return "Keep latency and visual quality in a stable middle ground."
        case .efficiency:
            return "Prefer smoother interaction and lower thermal load."
        case .quality:
            return "Spend more headroom on stage polish when the device allows it."
        }
    }
}

struct ConversationPreface: Codable {
    var systemPrompt: String
    var starterMessages: [String]
}

struct LearnerProfile: Codable, Equatable {
    var preferredName: String
    var learningGoal: String
    var preferredMode: ConversationMode
    var cefrEstimate: CEFRLevel
    var favoriteTopics: [String]
    var commonMistakes: [String]
    var firstSessionAt: Date?
    var updatedAt: Date

    static let `default` = LearnerProfile(
        preferredName: "",
        learningGoal: "",
        preferredMode: .chat,
        cefrEstimate: .a2,
        favoriteTopics: [],
        commonMistakes: [],
        firstSessionAt: nil,
        updatedAt: .now
    )
}

struct CharacterProfile: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var displayName: String
    var roleDescription: String
    var defaultSceneID: String
    var animationResourceID: String
    var defaultVoiceIdentifier: String?
    var speakingStyle: String
    var greetingStyle: String
    var coachingEnergy: String
    var heroHeadline: String
}

struct CharacterScene: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var title: String
    var ambienceDescription: String
    var backdropStyle: String
    var lightingStyle: String
}

enum VideoCallVisualStyle: String, Codable, CaseIterable, Identifiable {
    case natural
    case cinematic
    case softFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural:
            return "Natural"
        case .cinematic:
            return "Cinematic"
        case .softFocus:
            return "Soft Focus"
        }
    }

    var subtitle: String {
        switch self {
        case .natural:
            return "Clean skin tones and balanced lighting."
        case .cinematic:
            return "Higher contrast with deeper shadows."
        case .softFocus:
            return "Warmer glow with gentler edges."
        }
    }
}

struct CharacterPackManifest: Codable, Equatable, Hashable {
    var characterID: String
    var sceneIDs: [String]
    var animationResourceID: String
    var fallbackArtworkID: String
    var lipSyncStyle: String
}

struct LanguageProfile: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var displayName: String
    var conversationLanguage: String
    var explanationLanguage: String
    var asrLocale: String
    var ttsLanguageCode: String
    var ttsVoiceSet: [String]
    var bundledASRModelID: String? = nil
    var bundledTTSModelID: String? = nil
    var supportsTutor: Bool
    var supportsPronunciationDrill: Bool
    var supportsSpeechConversation: Bool = false
    var supportsChineseExplanationText: Bool = false
}

struct VoiceBundle: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var displayName: String
    var characterID: String?
    var languageProfileID: String
    var voiceIdentifier: String?
    var languageCode: String
    var pitchMultiplier: Float
    var rateMultiplier: Float
    var styleDescription: String
    var accent: EnglishAccent = .american
    var genderPresentation: VoiceGenderPresentation = .female
    var ttsModelFamily: TTSModelFamily = .kokoro
    var localVoiceAssetID: String? = nil
    var runtimeVoiceID: String? = nil
    var runtimeSpeakerKey: String? = nil
    var runtimeSpeakerID: Int = 0
    var pronunciationLexiconID: String? = nil
    var emotionPreset: VoiceEmotionPreset = .neutral
    var prosodyPolicy: SpeechProsodyPolicy = .chatWarm
    var chunkingPolicy: SpeechChunkingPolicy = .adaptive
    var prewarmRequired: Bool = false
    var isUserVisible: Bool = true
    var isReleaseReady: Bool = false
}

struct CharacterBundle: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var characterProfile: CharacterProfile
    var sceneIDs: [String]
    var visualVariants: [VideoCallVisualStyle]
    var voiceBundleIDs: [String]
    var openingPrompts: [String]
    var memoryTone: String
    var fallbackArtworkID: String
    var renderRuntimeKind: CharacterRenderRuntimeKind
    var portraitProfileID: String?
    var isReleaseReady: Bool
    var lipSyncStrategy: String = "energy-driven"
    var speechAnimationTuning: String = "balanced"
    var releaseTier: CharacterReleaseTier = .future
}

struct PerformanceSnapshot: Codable, Equatable {
    var tier: PerformanceTier
    var backendPreference: InferenceBackendPreference
    var lowPowerModeEnabled: Bool
    var speechRuntimeStatus: SpeechRuntimeStatusSnapshot = .fallbackDefault

    init(
        tier: PerformanceTier,
        backendPreference: InferenceBackendPreference,
        lowPowerModeEnabled: Bool,
        speechRuntimeStatus: SpeechRuntimeStatusSnapshot = .fallbackDefault
    ) {
        self.tier = tier
        self.backendPreference = backendPreference
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.speechRuntimeStatus = speechRuntimeStatus
    }

    private enum CodingKeys: String, CodingKey {
        case tier
        case backendPreference
        case lowPowerModeEnabled
        case speechRuntimeStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tier = try container.decode(PerformanceTier.self, forKey: .tier)
        backendPreference = try container.decode(InferenceBackendPreference.self, forKey: .backendPreference)
        lowPowerModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .lowPowerModeEnabled) ?? false
        speechRuntimeStatus = try container.decodeIfPresent(SpeechRuntimeStatusSnapshot.self, forKey: .speechRuntimeStatus)
            ?? .fallbackDefault
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tier, forKey: .tier)
        try container.encode(backendPreference, forKey: .backendPreference)
        try container.encode(lowPowerModeEnabled, forKey: .lowPowerModeEnabled)
        try container.encode(speechRuntimeStatus, forKey: .speechRuntimeStatus)
    }
}

struct ReleaseValidationBudget: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var title: String
    var budgetMilliseconds: Int
}

struct ReleaseValidationSpec: Codable, Equatable {
    var versionLabel: String
    var budgets: [ReleaseValidationBudget]
    var blockingConditions: [String]

    static let current = ReleaseValidationSpec(
        versionLabel: "2026-04-14",
        budgets: [
            ReleaseValidationBudget(id: "first-caption", title: "Start call to first assistant caption", budgetMilliseconds: 1800),
            ReleaseValidationBudget(id: "asr-partial", title: "Speech to partial transcript", budgetMilliseconds: 700),
            ReleaseValidationBudget(id: "speech-start", title: "Caption to assistant speech start", budgetMilliseconds: 900),
            ReleaseValidationBudget(id: "barge-in-stop", title: "Barge-in to stop", budgetMilliseconds: 500),
            ReleaseValidationBudget(id: "lip-sync-delay", title: "Assistant speech to lip-sync start", budgetMilliseconds: 120),
            ReleaseValidationBudget(id: "subtitle-drag", title: "Subtitle drag response", budgetMilliseconds: 16),
            ReleaseValidationBudget(id: "keyboard-open", title: "Keyboard open latency", budgetMilliseconds: 180)
        ],
        blockingConditions: [
            "Any happy-path call that lands in Attention needed before first assistant speech.",
            "Any character/scene combination with unreadable subtitle contrast.",
            "Any call flow where home/history/settings re-render with live transcript churn.",
            "Any call flow where route recovery or interruption handling leaves the microphone or assistant audio stuck."
        ]
    )
}

struct SpeechRuntimeSelectionSnapshot: Codable, Equatable, Hashable, Sendable {
    var conversationLanguageID: String
    var voiceBundleID: String
    var runtimeStatus: SpeechRuntimeStatusSnapshot
    var prefersBundledASR: Bool
    var prefersBundledTTS: Bool
    var degradedReasons: [String]

    var usesFallbackRuntime: Bool {
        runtimeStatus.usesFallbackRuntime
    }

    init(
        conversationLanguageID: String,
        voiceBundleID: String,
        runtimeStatus: SpeechRuntimeStatusSnapshot
    ) {
        self.conversationLanguageID = conversationLanguageID
        self.voiceBundleID = voiceBundleID
        self.runtimeStatus = runtimeStatus
        prefersBundledASR = runtimeStatus.asr.preferredAssetID?.hasPrefix("system-") == false
        prefersBundledTTS = runtimeStatus.tts.preferredAssetID?.hasPrefix("system-") == false
        degradedReasons = [
            runtimeStatus.asr.fallbackReason,
            runtimeStatus.tts.fallbackReason
        ].compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

struct CallReadinessSnapshot: Codable, Equatable, Hashable, Sendable {
    var disposition: CallReadinessDisposition
    var inputMode: CallInputMode?
    var capabilityStatus: SpeechCapabilityStatus
    var modelReady: Bool
    var modelStatusMessage: String
    var runtimeSelection: SpeechRuntimeSelectionSnapshot
    var requestedBackend: InferenceBackendPreference
    var effectiveBackend: InferenceBackendPreference
    var degradedReason: String?
    var evaluatedAt: Date
}

struct CharacterStageLayoutSpec: Codable, Equatable, Hashable {
    var surfaceKind: CharacterSurfaceKind
    var heroWidthRatio: Double
    var heroHeightRatio: Double
    var verticalBias: Double
    var subtitleBaselineRatio: Double
    var controlsBottomInset: Double
}

struct CharacterContinuitySnapshot: Codable, Equatable, Hashable {
    var surfaceKind: CharacterSurfaceKind
    var characterID: String
    var characterBundleID: String
    var sceneID: String
    var voiceBundleID: String
    var visualStyle: VideoCallVisualStyle
    var updatedAt: Date
}

extension CharacterStageLayoutSpec {
    static func releaseDefault(for surfaceKind: CharacterSurfaceKind) -> CharacterStageLayoutSpec {
        switch surfaceKind {
        case .homeHero:
            return CharacterStageLayoutSpec(
                surfaceKind: surfaceKind,
                heroWidthRatio: 0.54,
                heroHeightRatio: 0.34,
                verticalBias: 0.02,
                subtitleBaselineRatio: 0.78,
                controlsBottomInset: 34
            )
        case .quickStartPreview:
            return CharacterStageLayoutSpec(
                surfaceKind: surfaceKind,
                heroWidthRatio: 0.42,
                heroHeightRatio: 0.24,
                verticalBias: 0.01,
                subtitleBaselineRatio: 0.82,
                controlsBottomInset: 28
            )
        case .callHero:
            return CharacterStageLayoutSpec(
                surfaceKind: surfaceKind,
                heroWidthRatio: 0.88,
                heroHeightRatio: 0.54,
                verticalBias: -0.02,
                subtitleBaselineRatio: 0.67,
                controlsBottomInset: 122
            )
        case .historyPreview:
            return CharacterStageLayoutSpec(
                surfaceKind: surfaceKind,
                heroWidthRatio: 0.48,
                heroHeightRatio: 0.32,
                verticalBias: 0.0,
                subtitleBaselineRatio: 0.82,
                controlsBottomInset: 20
            )
        case .feedbackHero:
            return CharacterStageLayoutSpec(
                surfaceKind: surfaceKind,
                heroWidthRatio: 0.38,
                heroHeightRatio: 0.22,
                verticalBias: 0.0,
                subtitleBaselineRatio: 0.84,
                controlsBottomInset: 18
            )
        case .settingsPreview:
            return CharacterStageLayoutSpec(
                surfaceKind: surfaceKind,
                heroWidthRatio: 0.34,
                heroHeightRatio: 0.22,
                verticalBias: 0.0,
                subtitleBaselineRatio: 0.84,
                controlsBottomInset: 18
            )
        }
    }

    func stageSize(in containerSize: CGSize) -> CGSize {
        CGSize(
            width: max(88, containerSize.width * heroWidthRatio),
            height: max(112, containerSize.height * heroHeightRatio)
        )
    }

    func verticalOffset(in containerSize: CGSize) -> CGFloat {
        containerSize.height * verticalBias
    }

    func subtitleBaseline(in containerHeight: CGFloat) -> CGFloat {
        containerHeight * subtitleBaselineRatio
    }

    func controlsInset(safeAreaBottom: CGFloat) -> CGFloat {
        controlsBottomInset + safeAreaBottom
    }
}

extension CharacterSurfaceKind {
    var defaultLayoutSpec: CharacterStageLayoutSpec {
        CharacterStageLayoutSpec.releaseDefault(for: self)
    }

    var prefersContinuousAnimation: Bool {
        self == .callHero
    }
}

extension CharacterContinuitySnapshot {
    init(
        surfaceKind: CharacterSurfaceKind,
        characterID: String,
        sceneID: String,
        voiceBundleID: String,
        visualStyle: VideoCallVisualStyle,
        updatedAt: Date = .now
    ) {
        let normalizedCharacterID = CharacterCatalog.profile(for: characterID).id
        self.init(
            surfaceKind: surfaceKind,
            characterID: normalizedCharacterID,
            characterBundleID: CharacterCatalog.bundle(for: normalizedCharacterID).id,
            sceneID: CharacterCatalog.scene(for: sceneID, characterID: normalizedCharacterID).id,
            voiceBundleID: voiceBundleID,
            visualStyle: visualStyle,
            updatedAt: updatedAt
        )
    }

    static func resolve(
        surfaceKind: CharacterSurfaceKind,
        settings: CompanionSettings,
        session: ConversationSession? = nil
    ) -> CharacterContinuitySnapshot {
        let characterID = session?.characterID ?? settings.selectedCharacterID
        let sceneID = session?.sceneID ?? settings.selectedSceneID
        let voiceBundleID = session?.voiceBundleID ?? settings.selectedVoiceBundleID
        return CharacterContinuitySnapshot(
            surfaceKind: surfaceKind,
            characterID: characterID,
            sceneID: sceneID,
            voiceBundleID: voiceBundleID,
            visualStyle: settings.visualStyle
        )
    }
}

struct BundleAuditIssue: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var severity: String
    var message: String

    init(id: UUID = UUID(), severity: String, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}

struct BundleAuditReport: Codable, Equatable, Hashable {
    var generatedAt: Date
    var embeddedModelIDs: [String]
    var speechAssetIDs: [String]
    var issues: [BundleAuditIssue]

    var hasBlockingIssue: Bool {
        issues.contains { $0.severity.caseInsensitiveCompare("error") == .orderedSame }
    }
}

struct ValidationBudgetResult: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var title: String
    var budgetMilliseconds: Int
    var measuredMilliseconds: Int?
    var passed: Bool?
}

struct ValidationRunSnapshot: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var specVersionLabel: String
    var sessionID: UUID?
    var budgetResults: [ValidationBudgetResult]
    var blockingIssues: [String]
    var overallPassed: Bool
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        specVersionLabel: String,
        sessionID: UUID? = nil,
        budgetResults: [ValidationBudgetResult],
        blockingIssues: [String],
        overallPassed: Bool,
        generatedAt: Date = .now
    ) {
        self.id = id
        self.specVersionLabel = specVersionLabel
        self.sessionID = sessionID
        self.budgetResults = budgetResults
        self.blockingIssues = blockingIssues
        self.overallPassed = overallPassed
        self.generatedAt = generatedAt
    }
}

struct UserDataSnapshot: Codable, Equatable {
    var learnerProfile: LearnerProfile
    var companionSettings: CompanionSettings
    var sessions: [ConversationSession]
    var threadStates: [ConversationThreadState]
    var vocabulary: [VocabularyItem]

    init(
        learnerProfile: LearnerProfile,
        companionSettings: CompanionSettings,
        sessions: [ConversationSession],
        threadStates: [ConversationThreadState],
        vocabulary: [VocabularyItem]
    ) {
        self.learnerProfile = learnerProfile
        self.companionSettings = companionSettings
        self.sessions = sessions
        self.threadStates = threadStates
        self.vocabulary = vocabulary
    }

    init(memorySnapshot: MemorySnapshot) {
        self.init(
            learnerProfile: memorySnapshot.learnerProfile,
            companionSettings: memorySnapshot.companionSettings,
            sessions: memorySnapshot.sessions,
            threadStates: memorySnapshot.threadStates,
            vocabulary: memorySnapshot.vocabulary
        )
    }
}

struct ModelStateSnapshot: Codable, Equatable {
    var modelInstallationRecords: [ModelInstallationRecord]
    var modelSelectionState: ModelSelectionState

    init(
        modelInstallationRecords: [ModelInstallationRecord],
        modelSelectionState: ModelSelectionState
    ) {
        self.modelInstallationRecords = modelInstallationRecords
        self.modelSelectionState = modelSelectionState
    }

    init(memorySnapshot: MemorySnapshot) {
        self.init(
            modelInstallationRecords: memorySnapshot.modelInstallationRecords,
            modelSelectionState: memorySnapshot.modelSelectionState
        )
    }
}

struct AssetStateSnapshot: Codable, Equatable {
    var bundledSpeechAssetIDs: [String]
    var bundleAuditReport: BundleAuditReport?
    var latestValidationSnapshot: ValidationRunSnapshot?
    var updatedAt: Date

    init(
        bundledSpeechAssetIDs: [String] = [],
        bundleAuditReport: BundleAuditReport? = nil,
        latestValidationSnapshot: ValidationRunSnapshot? = nil,
        updatedAt: Date = .now
    ) {
        self.bundledSpeechAssetIDs = bundledSpeechAssetIDs
        self.bundleAuditReport = bundleAuditReport
        self.latestValidationSnapshot = latestValidationSnapshot
        self.updatedAt = updatedAt
    }
}

enum PersistenceInstallDisposition: String, Codable, Equatable, Hashable {
    case freshInstall
    case upgrade
    case reinstall
}

struct PersistenceMigrationReceipt: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    var sourceVersion: Int
    var targetVersion: Int
    var installDisposition: PersistenceInstallDisposition
    var migratedAt: Date
    var backupFileName: String?

    init(
        id: UUID = UUID(),
        sourceVersion: Int,
        targetVersion: Int,
        installDisposition: PersistenceInstallDisposition,
        migratedAt: Date = .now,
        backupFileName: String? = nil
    ) {
        self.id = id
        self.sourceVersion = sourceVersion
        self.targetVersion = targetVersion
        self.installDisposition = installDisposition
        self.migratedAt = migratedAt
        self.backupFileName = backupFileName
    }
}

struct CompanionSettings: Codable, Equatable {
    var selectedCharacterID: String
    var selectedSceneID: String
    var selectedVoiceBundleID: String
    var conversationLanguageID: String
    var explanationLanguageID: String
    var visualStyle: VideoCallVisualStyle
    var speechRate: Float
    var allowChineseHints: Bool
    var backendPreference: InferenceBackendPreference
    var preferredVoiceIdentifier: String?
    var portraitModeEnabled: Bool
    var performanceTier: PerformanceTier
    var warmupCompleted: Bool

    static let `default` = CompanionSettings(
        selectedCharacterID: CharacterCatalog.flagship.id,
        selectedSceneID: CharacterCatalog.flagship.defaultSceneID,
        selectedVoiceBundleID: VoiceCatalog.defaultBundle(
            for: CharacterCatalog.flagship.id,
            languageID: LanguageCatalog.english.id
        ).id,
        conversationLanguageID: LanguageCatalog.english.id,
        explanationLanguageID: LanguageCatalog.simplifiedChinese.id,
        visualStyle: .natural,
        speechRate: 0.47,
        allowChineseHints: true,
        backendPreference: .gpu,
        preferredVoiceIdentifier: nil,
        portraitModeEnabled: CharacterCatalog.primaryPortraitAvailable,
        performanceTier: .balanced,
        warmupCompleted: false
    )

    init(
        selectedCharacterID: String,
        selectedSceneID: String,
        selectedVoiceBundleID: String,
        conversationLanguageID: String,
        explanationLanguageID: String,
        visualStyle: VideoCallVisualStyle,
        speechRate: Float,
        allowChineseHints: Bool,
        backendPreference: InferenceBackendPreference,
        preferredVoiceIdentifier: String?,
        portraitModeEnabled: Bool,
        performanceTier: PerformanceTier,
        warmupCompleted: Bool
    ) {
        self.selectedCharacterID = selectedCharacterID
        self.selectedSceneID = selectedSceneID
        self.selectedVoiceBundleID = selectedVoiceBundleID
        self.conversationLanguageID = conversationLanguageID
        self.explanationLanguageID = explanationLanguageID
        self.visualStyle = visualStyle
        self.speechRate = speechRate
        self.allowChineseHints = allowChineseHints
        self.backendPreference = backendPreference
        self.preferredVoiceIdentifier = preferredVoiceIdentifier
        self.portraitModeEnabled = portraitModeEnabled
        self.performanceTier = performanceTier
        self.warmupCompleted = warmupCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case selectedCharacterID
        case selectedSceneID
        case selectedVoiceBundleID
        case conversationLanguageID
        case explanationLanguageID
        case visualStyle
        case speechRate
        case allowChineseHints
        case backendPreference
        case preferredVoiceIdentifier
        case portraitModeEnabled
        case performanceTier
        case warmupCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedCharacterID = try container.decodeIfPresent(String.self, forKey: .selectedCharacterID) ?? CharacterCatalog.flagship.id
        selectedSceneID = try container.decodeIfPresent(String.self, forKey: .selectedSceneID) ?? CharacterCatalog.flagship.defaultSceneID
        conversationLanguageID = LanguageCatalog.profile(
            for: try container.decodeIfPresent(String.self, forKey: .conversationLanguageID) ?? LanguageCatalog.english.id
        ).id
        visualStyle = try container.decodeIfPresent(VideoCallVisualStyle.self, forKey: .visualStyle) ?? .natural
        speechRate = try container.decodeIfPresent(Float.self, forKey: .speechRate) ?? 0.47
        allowChineseHints = try container.decodeIfPresent(Bool.self, forKey: .allowChineseHints) ?? true
        explanationLanguageID = LanguageCatalog.profile(
            for: try container.decodeIfPresent(String.self, forKey: .explanationLanguageID)
                ?? (allowChineseHints ? LanguageCatalog.simplifiedChinese.id : LanguageCatalog.english.id)
        ).id
        backendPreference = try container.decodeIfPresent(InferenceBackendPreference.self, forKey: .backendPreference) ?? .gpu
        preferredVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .preferredVoiceIdentifier)
        let storedVoiceBundleID = try container.decodeIfPresent(String.self, forKey: .selectedVoiceBundleID)
        selectedVoiceBundleID = VoiceCatalog.bundle(
            for: storedVoiceBundleID,
            characterID: selectedCharacterID,
            languageID: conversationLanguageID
        ).id
        portraitModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .portraitModeEnabled) ?? CharacterCatalog.primaryPortraitAvailable
        performanceTier = try container.decodeIfPresent(PerformanceTier.self, forKey: .performanceTier) ?? .balanced
        warmupCompleted = try container.decodeIfPresent(Bool.self, forKey: .warmupCompleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedCharacterID, forKey: .selectedCharacterID)
        try container.encode(selectedSceneID, forKey: .selectedSceneID)
        try container.encode(selectedVoiceBundleID, forKey: .selectedVoiceBundleID)
        try container.encode(conversationLanguageID, forKey: .conversationLanguageID)
        try container.encode(explanationLanguageID, forKey: .explanationLanguageID)
        try container.encode(visualStyle, forKey: .visualStyle)
        try container.encode(speechRate, forKey: .speechRate)
        try container.encode(allowChineseHints, forKey: .allowChineseHints)
        try container.encode(backendPreference, forKey: .backendPreference)
        try container.encodeIfPresent(preferredVoiceIdentifier, forKey: .preferredVoiceIdentifier)
        try container.encode(portraitModeEnabled, forKey: .portraitModeEnabled)
        try container.encode(performanceTier, forKey: .performanceTier)
        try container.encode(warmupCompleted, forKey: .warmupCompleted)
    }
}

struct ScenarioPreset: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var category: ScenarioCategory
    var title: String
    var summary: String
    var openingGoal: String
    var followUpHint: String
    var suggestedReplyLength: String
    var preferredMode: ConversationMode
}

struct LearningFocusPlan: Codable, Equatable {
    var title: String
    var mission: String
    var checkpoint: String
    var successSignal: String
    var pronunciationFocus: [String]
    var carryOverVocabulary: [String]

    static func suggested(
        learner: LearnerProfile,
        scenario: ScenarioPreset,
        mode: ConversationMode,
        vocabulary: [VocabularyItem]
    ) -> LearningFocusPlan {
        let learnerGoal = learner.learningGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        let carryOverVocabulary = Array(vocabulary.prefix(3).map(\.term))
        let pronunciationFocus: [String]
        if learner.commonMistakes.contains(where: { $0.localizedCaseInsensitiveContains("th") }) {
            pronunciationFocus = ["think", "this", "those"]
        } else {
            pronunciationFocus = mode == .tutor ? ["reason", "really", "world"] : ["today", "because", "usually"]
        }

        return LearningFocusPlan(
            title: mode == .tutor ? "Micro-goal for this call" : "Flow target for this call",
            mission: learnerGoal.isEmpty ? scenario.openingGoal : learnerGoal,
            checkpoint: scenario.followUpHint,
            successSignal: mode == .tutor
                ? "Give one clearer answer with a reason and an example."
                : "Keep the conversation moving for three natural turns.",
            pronunciationFocus: pronunciationFocus,
            carryOverVocabulary: carryOverVocabulary
        )
    }

    static func continued(
        learner: LearnerProfile,
        scenario: ScenarioPreset,
        mode: ConversationMode,
        vocabulary: [VocabularyItem],
        previousSession: ConversationSession
    ) -> LearningFocusPlan {
        let fallback = suggested(
            learner: learner,
            scenario: scenario,
            mode: mode,
            vocabulary: vocabulary
        )

        let previousPlan = previousSession.learningPlanSnapshot
        let previousFeedback = previousSession.feedbackReport
        let inheritedMission = previousFeedback?.nextMission.nonEmpty
            ?? previousPlan?.mission.nonEmpty
            ?? fallback.mission
        let inheritedCheckpoint = previousFeedback?.continuationCue.nonEmpty
            ?? previousPlan?.checkpoint.nonEmpty
            ?? scenario.followUpHint
        let inheritedSuccessSignal = previousPlan?.successSignal.nonEmpty
            ?? fallback.successSignal
        let inheritedCarryOver = previousFeedback?.carryOverVocabulary.nonEmptyArray
            ?? previousPlan?.carryOverVocabulary.nonEmptyArray
            ?? fallback.carryOverVocabulary
        let inheritedPronunciation = previousPlan?.pronunciationFocus.nonEmptyArray
            ?? previousFeedback?.pronunciationTargetTokens.nonEmptyArray
            ?? fallback.pronunciationFocus

        return LearningFocusPlan(
            title: mode == .tutor ? "Continued mission" : "Continued flow target",
            mission: inheritedMission,
            checkpoint: inheritedCheckpoint,
            successSignal: inheritedSuccessSignal,
            pronunciationFocus: inheritedPronunciation,
            carryOverVocabulary: inheritedCarryOver
        )
    }
}

struct SubtitleOverlayState: Equatable {
    var mode: SubtitleOverlayMode = .collapsed
    var currentHeight: Double = 0
    var dragOffset: Double = 0
    var primarySpeaker: SubtitleSpeaker = .assistant
    var liveText: String = ""
}

struct CorrectionEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var category: FeedbackCategory
    var source: String
    var suggestion: String
    var explanation: String

    init(id: UUID = UUID(), category: FeedbackCategory, source: String, suggestion: String, explanation: String) {
        self.id = id
        self.category = category
        self.source = source
        self.suggestion = suggestion
        self.explanation = explanation
    }
}

struct VocabularyItem: Codable, Identifiable, Equatable {
    let id: UUID
    var term: String
    var translation: String
    var example: String
    var encounterCount: Int
    var mastery: VocabularyMastery
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        term: String,
        translation: String,
        example: String,
        encounterCount: Int = 1,
        mastery: VocabularyMastery = .new,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.term = term
        self.translation = translation
        self.example = example
        self.encounterCount = encounterCount
        self.mastery = mastery
        self.updatedAt = updatedAt
    }
}

struct FeedbackReport: Codable, Identifiable, Equatable {
    let id: UUID
    var grammarIssues: [CorrectionEvent]
    var vocabularySuggestions: [CorrectionEvent]
    var pronunciationTips: [CorrectionEvent]
    var frequentExpressions: [String]
    var nextTopicSuggestions: [String]
    var pronunciationHighlights: [String]
    var carryOverVocabulary: [String]
    var nextMission: String
    var nextThemeSuggestion: String
    var continuationCue: String
    var goalCompletionSummary: String
    var voiceBundleID: String?
    var voiceDisplayName: String
    var referenceAccent: EnglishAccent
    var referenceAccentDisplayName: String
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        grammarIssues: [CorrectionEvent] = [],
        vocabularySuggestions: [CorrectionEvent] = [],
        pronunciationTips: [CorrectionEvent] = [],
        frequentExpressions: [String] = [],
        nextTopicSuggestions: [String] = [],
        pronunciationHighlights: [String] = [],
        carryOverVocabulary: [String] = [],
        nextMission: String = "Keep the same character and push one longer reply next time.",
        nextThemeSuggestion: String = "Stay with the same character and open one adjacent theme next time.",
        continuationCue: String = "Resume the same thread and reuse one phrase from this call.",
        goalCompletionSummary: String = "This session created a solid next step for your speaking practice.",
        voiceBundleID: String? = nil,
        voiceDisplayName: String = "American Female",
        referenceAccent: EnglishAccent = .american,
        referenceAccentDisplayName: String = EnglishAccent.american.displayName,
        generatedAt: Date = .now
    ) {
        self.id = id
        self.grammarIssues = grammarIssues
        self.vocabularySuggestions = vocabularySuggestions
        self.pronunciationTips = pronunciationTips
        self.frequentExpressions = frequentExpressions
        self.nextTopicSuggestions = nextTopicSuggestions
        self.pronunciationHighlights = pronunciationHighlights
        self.carryOverVocabulary = carryOverVocabulary
        self.nextMission = nextMission
        self.nextThemeSuggestion = nextThemeSuggestion
        self.continuationCue = continuationCue
        self.goalCompletionSummary = goalCompletionSummary
        self.voiceBundleID = voiceBundleID
        self.voiceDisplayName = voiceDisplayName
        self.referenceAccent = referenceAccent
        self.referenceAccentDisplayName = referenceAccentDisplayName
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case grammarIssues
        case vocabularySuggestions
        case pronunciationTips
        case frequentExpressions
        case nextTopicSuggestions
        case pronunciationHighlights
        case carryOverVocabulary
        case nextMission
        case nextThemeSuggestion
        case continuationCue
        case goalCompletionSummary
        case voiceBundleID
        case voiceDisplayName
        case referenceAccent
        case referenceAccentDisplayName
        case generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        grammarIssues = try container.decodeIfPresent([CorrectionEvent].self, forKey: .grammarIssues) ?? []
        vocabularySuggestions = try container.decodeIfPresent([CorrectionEvent].self, forKey: .vocabularySuggestions) ?? []
        pronunciationTips = try container.decodeIfPresent([CorrectionEvent].self, forKey: .pronunciationTips) ?? []
        frequentExpressions = try container.decodeIfPresent([String].self, forKey: .frequentExpressions) ?? []
        nextTopicSuggestions = try container.decodeIfPresent([String].self, forKey: .nextTopicSuggestions) ?? []
        pronunciationHighlights = try container.decodeIfPresent([String].self, forKey: .pronunciationHighlights) ?? []
        carryOverVocabulary = try container.decodeIfPresent([String].self, forKey: .carryOverVocabulary) ?? []
        nextMission = try container.decodeIfPresent(String.self, forKey: .nextMission) ?? "Keep the same character and push one longer reply next time."
        nextThemeSuggestion = try container.decodeIfPresent(String.self, forKey: .nextThemeSuggestion) ?? "Stay with the same character and open one adjacent theme next time."
        continuationCue = try container.decodeIfPresent(String.self, forKey: .continuationCue) ?? "Resume the same thread and reuse one phrase from this call."
        goalCompletionSummary = try container.decodeIfPresent(String.self, forKey: .goalCompletionSummary) ?? "This session created a solid next step for your speaking practice."
        voiceBundleID = try container.decodeIfPresent(String.self, forKey: .voiceBundleID)
        referenceAccent = try container.decodeIfPresent(EnglishAccent.self, forKey: .referenceAccent) ?? .american
        voiceDisplayName = try container.decodeIfPresent(String.self, forKey: .voiceDisplayName)
            ?? VoiceCatalog.bundle(
                for: voiceBundleID,
                characterID: CharacterCatalog.flagship.id,
                languageID: LanguageCatalog.english.id
            ).displayName
        referenceAccentDisplayName = try container.decodeIfPresent(String.self, forKey: .referenceAccentDisplayName)
            ?? referenceAccent.displayName
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
    }
}

struct ConversationTurn: Codable, Identifiable, Equatable {
    let id: UUID
    var role: TurnRole
    var text: String
    var timestamp: Date
    var corrections: [CorrectionEvent]
    var wasInterrupted: Bool

    init(
        id: UUID = UUID(),
        role: TurnRole,
        text: String,
        timestamp: Date = .now,
        corrections: [CorrectionEvent] = [],
        wasInterrupted: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.corrections = corrections
        self.wasInterrupted = wasInterrupted
    }
}

struct ConversationSession: Codable, Identifiable, Equatable {
    let id: UUID
    var mode: ConversationMode
    var startedAt: Date
    var endedAt: Date?
    var summary: String
    var keyMoments: [String]
    var turns: [ConversationTurn]
    var feedbackReport: FeedbackReport?
    var characterID: String
    var characterBundleID: String
    var voiceBundleID: String
    var voiceAccent: EnglishAccent
    var sceneID: String
    var scenarioID: String?
    var scenarioCategory: ScenarioCategory?
    var languageProfileID: String
    var continuationThreadID: String
    var performanceSnapshot: PerformanceSnapshot
    var runtimeSelection: SpeechRuntimeSelectionSnapshot?
    var learningPlanSnapshot: LearningFocusPlan?
    var speechMetrics: [SpeechTurnMetrics]
    var validationSnapshot: ValidationRunSnapshot?

    init(
        id: UUID = UUID(),
        mode: ConversationMode,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        summary: String = "",
        keyMoments: [String] = [],
        turns: [ConversationTurn] = [],
        feedbackReport: FeedbackReport? = nil,
        characterID: String = CharacterCatalog.flagship.id,
        characterBundleID: String = CharacterCatalog.bundle(for: CharacterCatalog.flagship.id).id,
        voiceBundleID: String = VoiceCatalog.defaultBundle(
            for: CharacterCatalog.flagship.id,
            languageID: LanguageCatalog.english.id
        ).id,
        voiceAccent: EnglishAccent = VoiceCatalog.defaultBundle(
            for: CharacterCatalog.flagship.id,
            languageID: LanguageCatalog.english.id
        ).accent,
        sceneID: String = CharacterCatalog.flagship.defaultSceneID,
        scenarioID: String? = nil,
        scenarioCategory: ScenarioCategory? = nil,
        languageProfileID: String = LanguageCatalog.english.id,
        continuationThreadID: String = UUID().uuidString,
        performanceSnapshot: PerformanceSnapshot = PerformanceSnapshot(
            tier: .balanced,
            backendPreference: .gpu,
            lowPowerModeEnabled: false
        ),
        runtimeSelection: SpeechRuntimeSelectionSnapshot? = nil,
        learningPlanSnapshot: LearningFocusPlan? = nil,
        speechMetrics: [SpeechTurnMetrics] = [],
        validationSnapshot: ValidationRunSnapshot? = nil
    ) {
        self.id = id
        self.mode = mode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.keyMoments = keyMoments
        self.turns = turns
        self.feedbackReport = feedbackReport
        self.characterID = characterID
        self.characterBundleID = characterBundleID
        self.voiceBundleID = voiceBundleID
        self.voiceAccent = voiceAccent
        self.sceneID = sceneID
        self.scenarioID = scenarioID
        self.scenarioCategory = scenarioCategory
        self.languageProfileID = languageProfileID
        self.continuationThreadID = continuationThreadID
        self.performanceSnapshot = performanceSnapshot
        self.runtimeSelection = runtimeSelection
        self.learningPlanSnapshot = learningPlanSnapshot
        self.speechMetrics = speechMetrics
        self.validationSnapshot = validationSnapshot
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mode
        case startedAt
        case endedAt
        case summary
        case keyMoments
        case turns
        case feedbackReport
        case characterID
        case characterBundleID
        case voiceBundleID
        case voiceAccent
        case sceneID
        case scenarioID
        case scenarioCategory
        case languageProfileID
        case continuationThreadID
        case performanceSnapshot
        case runtimeSelection
        case learningPlanSnapshot
        case speechMetrics
        case validationSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mode = try container.decode(ConversationMode.self, forKey: .mode)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? .now
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        keyMoments = try container.decodeIfPresent([String].self, forKey: .keyMoments) ?? []
        turns = try container.decodeIfPresent([ConversationTurn].self, forKey: .turns) ?? []
        feedbackReport = try container.decodeIfPresent(FeedbackReport.self, forKey: .feedbackReport)
        let decodedCharacterID = try container.decodeIfPresent(String.self, forKey: .characterID) ?? CharacterCatalog.flagship.id
        characterID = CharacterCatalog.profile(for: decodedCharacterID).id
        characterBundleID = try container.decodeIfPresent(String.self, forKey: .characterBundleID)
            ?? CharacterCatalog.bundle(for: characterID).id
        languageProfileID = LanguageCatalog.profile(
            for: try container.decodeIfPresent(String.self, forKey: .languageProfileID) ?? LanguageCatalog.english.id
        ).id
        voiceBundleID = VoiceCatalog.bundle(
            for: try container.decodeIfPresent(String.self, forKey: .voiceBundleID),
            characterID: characterID,
            languageID: languageProfileID
        ).id
        voiceAccent = try container.decodeIfPresent(EnglishAccent.self, forKey: .voiceAccent)
            ?? VoiceCatalog.bundle(
                for: voiceBundleID,
                characterID: characterID,
                languageID: languageProfileID
            ).accent
        let defaultSceneID = CharacterCatalog.defaultScene(for: characterID).id
        sceneID = try container.decodeIfPresent(String.self, forKey: .sceneID) ?? defaultSceneID
        scenarioID = try container.decodeIfPresent(String.self, forKey: .scenarioID)
        scenarioCategory = try container.decodeIfPresent(ScenarioCategory.self, forKey: .scenarioCategory)
        continuationThreadID = try container.decodeIfPresent(String.self, forKey: .continuationThreadID) ?? id.uuidString
        performanceSnapshot = try container.decodeIfPresent(PerformanceSnapshot.self, forKey: .performanceSnapshot)
            ?? PerformanceSnapshot(tier: .balanced, backendPreference: .gpu, lowPowerModeEnabled: false)
        runtimeSelection = try container.decodeIfPresent(SpeechRuntimeSelectionSnapshot.self, forKey: .runtimeSelection)
        learningPlanSnapshot = try container.decodeIfPresent(LearningFocusPlan.self, forKey: .learningPlanSnapshot)
        speechMetrics = try container.decodeIfPresent([SpeechTurnMetrics].self, forKey: .speechMetrics) ?? []
        validationSnapshot = try container.decodeIfPresent(ValidationRunSnapshot.self, forKey: .validationSnapshot)
    }
}

struct ConversationThreadState: Codable, Equatable, Identifiable {
    let id: String
    var latestSessionID: UUID
    var mode: ConversationMode
    var characterID: String
    var sceneID: String
    var voiceBundleID: String
    var languageProfileID: String
    var scenarioID: String?
    var currentMission: String
    var checkpoint: String
    var successSignal: String
    var carryOverVocabulary: [String]
    var pronunciationTargets: [String]
    var nextMission: String
    var nextThemeSuggestion: String
    var continuationCue: String
    var goalCompletionSummary: String
    var summary: String
    var updatedAt: Date

    init(session: ConversationSession) {
        let learningPlan = session.learningPlanSnapshot
        let feedback = session.feedbackReport

        id = session.continuationThreadID
        latestSessionID = session.id
        mode = session.mode
        characterID = session.characterID
        sceneID = session.sceneID
        voiceBundleID = session.voiceBundleID
        languageProfileID = session.languageProfileID
        scenarioID = session.scenarioID
        currentMission = learningPlan?.mission.nonEmpty
            ?? feedback?.nextMission.nonEmpty
            ?? "Keep this same character thread moving with one clearer reply."
        checkpoint = learningPlan?.checkpoint.nonEmpty
            ?? feedback?.continuationCue.nonEmpty
            ?? "Resume from the previous thread and add one more concrete detail."
        successSignal = learningPlan?.successSignal.nonEmpty
            ?? "Keep the thread going without dropping back to one-line answers."
        carryOverVocabulary = feedback?.carryOverVocabulary.nonEmptyArray
            ?? learningPlan?.carryOverVocabulary.nonEmptyArray
            ?? []
        pronunciationTargets = learningPlan?.pronunciationFocus.nonEmptyArray
            ?? feedback?.pronunciationTargetTokens.nonEmptyArray
            ?? []
        nextMission = feedback?.nextMission.nonEmpty
            ?? learningPlan?.mission.nonEmpty
            ?? currentMission
        nextThemeSuggestion = feedback?.nextThemeSuggestion.nonEmpty
            ?? ScenarioCatalog.preset(for: session.scenarioID, mode: session.mode).summary
        continuationCue = feedback?.continuationCue.nonEmpty
            ?? checkpoint
        goalCompletionSummary = feedback?.goalCompletionSummary.nonEmpty
            ?? "This thread is ready to continue from the latest local checkpoint."
        summary = session.summary.nonEmpty
            ?? session.turns.last?.text.nonEmpty
            ?? continuationCue
        updatedAt = session.endedAt ?? session.startedAt
    }

    static func derived(from sessions: [ConversationSession]) -> [ConversationThreadState] {
        Dictionary(grouping: sessions, by: \.continuationThreadID)
            .compactMap { _, grouped in
                guard let latest = grouped.max(by: { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }) else {
                    return nil
                }
                return ConversationThreadState(session: latest)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

enum ModelPackagingType: String, Codable {
    case bundledBase
    case downloadable
}

enum ModelRuntimeFamily: String, Codable {
    case litertLM
}

enum ModelArtifactSource: String, Codable {
    case bundledApp
    case downloaded
}

enum ActiveModelReadiness: Equatable {
    case ready
    case unavailable(String)
}

struct ModelDescriptor: Codable, Equatable, Identifiable {
    let id: String
    var displayName: String
    var packagingType: ModelPackagingType
    var runtimeFamily: ModelRuntimeFamily
    var version: String
    var fileName: String
    var expectedFileSizeBytes: Int64
    var checksum: String?
    var downloadURL: URL?
    var isSelectable: Bool
    var isDeletable: Bool

    var isBundledBase: Bool {
        packagingType == .bundledBase
    }
}

struct ModelInstallationRecord: Codable, Equatable, Identifiable {
    var id: String { modelID }

    var modelID: String
    var status: ModelInstallStatus
    var checksum: String?
    var integrityCheckPassed: Bool
    var resolvedURL: URL?
    var fileSizeBytes: Int64?
    var lastValidatedAt: Date?
    var lastUsedAt: Date?
    var failureReason: String?
    var progress: Double
    var artifactSource: ModelArtifactSource?

    var isReadyForInference: Bool {
        status == .installed && integrityCheckPassed && resolvedURL != nil
    }

    var isEmbeddedInApp: Bool {
        artifactSource == .bundledApp
    }

    var canDeleteInstalledArtifact: Bool {
        artifactSource == .downloaded && (status == .installed || status == .corrupted || status == .failed)
    }
}

struct ModelSelectionState: Codable, Equatable {
    var selectedModelID: String
    var defaultModelID: String
}

struct ModelCatalog: Equatable {
    var descriptors: [ModelDescriptor]

    static let bundledGemma4E2B = ModelDescriptor(
        id: "gemma-4-e2b",
        displayName: "Gemma 4 E2B",
        packagingType: .bundledBase,
        runtimeFamily: .litertLM,
        version: "gemma-4-e2b-v1",
        fileName: "gemma-4-E2B-it.litertlm",
        expectedFileSizeBytes: 2_583_085_056,
        checksum: nil,
        downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true"),
        isSelectable: true,
        isDeletable: false
    )

    static let current = ModelCatalog(descriptors: [
        bundledGemma4E2B
    ])

    var defaultDescriptor: ModelDescriptor {
        descriptor(for: defaultSelectionState.defaultModelID) ?? descriptors[0]
    }

    var defaultSelectionState: ModelSelectionState {
        ModelSelectionState(selectedModelID: Self.bundledGemma4E2B.id, defaultModelID: Self.bundledGemma4E2B.id)
    }

    func descriptor(for id: String) -> ModelDescriptor? {
        descriptors.first(where: { $0.id == id })
    }

    func defaultRecord(for modelID: String) -> ModelInstallationRecord {
        ModelInstallationRecord(
            modelID: modelID,
            status: .notInstalled,
            checksum: nil,
            integrityCheckPassed: false,
            resolvedURL: nil,
            fileSizeBytes: nil,
            lastValidatedAt: nil,
            lastUsedAt: nil,
            failureReason: nil,
            progress: 0,
            artifactSource: nil
        )
    }

    func defaultRecords() -> [ModelInstallationRecord] {
        descriptors.map { defaultRecord(for: $0.id) }
    }

    func mergedRecords(with storedRecords: [ModelInstallationRecord]) -> [ModelInstallationRecord] {
        let storedByID = Dictionary(uniqueKeysWithValues: storedRecords.map { ($0.modelID, $0) })
        return descriptors.map { descriptor in
            storedByID[descriptor.id] ?? defaultRecord(for: descriptor.id)
        }
    }
}

private struct LegacyModelInstallState: Codable, Equatable {
    var status: ModelInstallStatus
    var version: String
    var checksum: String?
    var fileSizeBytes: Int64?
    var expectedFileSizeBytes: Int64
    var integrityCheckPassed: Bool
    var isEmbeddedInApp: Bool
    var lastUsedAt: Date?
    var lastValidatedAt: Date?
    var progress: Double
    var fileName: String
    var downloadURL: URL?
    var failureReason: String?

    static let `default` = LegacyModelInstallState(
        status: .notInstalled,
        version: ModelCatalog.bundledGemma4E2B.version,
        checksum: nil,
        fileSizeBytes: nil,
        expectedFileSizeBytes: ModelCatalog.bundledGemma4E2B.expectedFileSizeBytes,
        integrityCheckPassed: false,
        isEmbeddedInApp: false,
        lastUsedAt: nil,
        lastValidatedAt: nil,
        progress: 0,
        fileName: ModelCatalog.bundledGemma4E2B.fileName,
        downloadURL: ModelCatalog.bundledGemma4E2B.downloadURL,
        failureReason: nil
    )

    func migratedRecord(for modelID: String) -> ModelInstallationRecord {
        ModelInstallationRecord(
            modelID: modelID,
            status: status,
            checksum: checksum,
            integrityCheckPassed: integrityCheckPassed,
            resolvedURL: nil,
            fileSizeBytes: fileSizeBytes,
            lastValidatedAt: lastValidatedAt,
            lastUsedAt: lastUsedAt,
            failureReason: failureReason,
            progress: progress,
            artifactSource: isEmbeddedInApp ? .bundledApp : (status == .notInstalled ? nil : .downloaded)
        )
    }
}

private struct LegacyPersonaState: Codable, Equatable {
    var personaName: String
    var roleDescription: String
    var speechRate: Float
    var allowChineseHints: Bool
    var backendPreference: InferenceBackendPreference
    var preferredVoiceIdentifier: String?
    var warmupCompleted: Bool
}

struct MemorySnapshot: Codable, Equatable {
    var learnerProfile: LearnerProfile
    var companionSettings: CompanionSettings
    var sessions: [ConversationSession]
    var threadStates: [ConversationThreadState]
    var vocabulary: [VocabularyItem]
    var modelInstallationRecords: [ModelInstallationRecord]
    var modelSelectionState: ModelSelectionState

    init(
        learnerProfile: LearnerProfile,
        companionSettings: CompanionSettings,
        sessions: [ConversationSession],
        threadStates: [ConversationThreadState],
        vocabulary: [VocabularyItem],
        modelInstallationRecords: [ModelInstallationRecord],
        modelSelectionState: ModelSelectionState
    ) {
        self.learnerProfile = learnerProfile
        self.companionSettings = companionSettings
        self.sessions = sessions
        self.threadStates = threadStates
        self.vocabulary = vocabulary
        self.modelInstallationRecords = modelInstallationRecords
        self.modelSelectionState = modelSelectionState
    }

    private enum CodingKeys: String, CodingKey {
        case learnerProfile
        case companionSettings
        case sessions
        case threadStates
        case vocabulary
        case modelInstallationRecords
        case modelSelectionState
        case modelInstallState
        case personaState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        learnerProfile = try container.decodeIfPresent(LearnerProfile.self, forKey: .learnerProfile) ?? .default
        sessions = try container.decodeIfPresent([ConversationSession].self, forKey: .sessions) ?? []
        threadStates = try container.decodeIfPresent([ConversationThreadState].self, forKey: .threadStates)
            ?? ConversationThreadState.derived(from: sessions)
        vocabulary = try container.decodeIfPresent([VocabularyItem].self, forKey: .vocabulary) ?? []

        if let settings = try container.decodeIfPresent(CompanionSettings.self, forKey: .companionSettings) {
            companionSettings = settings
        } else if let legacyPersona = try container.decodeIfPresent(LegacyPersonaState.self, forKey: .personaState) {
            companionSettings = CompanionSettings(
                selectedCharacterID: CharacterCatalog.flagship.id,
                selectedSceneID: CharacterCatalog.flagship.defaultSceneID,
                selectedVoiceBundleID: VoiceCatalog.defaultBundle(
                    for: CharacterCatalog.flagship.id,
                    languageID: LanguageCatalog.english.id
                ).id,
                conversationLanguageID: LanguageCatalog.english.id,
                explanationLanguageID: legacyPersona.allowChineseHints ? LanguageCatalog.simplifiedChinese.id : LanguageCatalog.english.id,
                visualStyle: .natural,
                speechRate: legacyPersona.speechRate,
                allowChineseHints: legacyPersona.allowChineseHints,
                backendPreference: legacyPersona.backendPreference,
                preferredVoiceIdentifier: legacyPersona.preferredVoiceIdentifier,
                portraitModeEnabled: CharacterCatalog.primaryPortraitAvailable,
                performanceTier: .balanced,
                warmupCompleted: legacyPersona.warmupCompleted
            )
        } else {
            companionSettings = .default
        }

        let catalog = ModelCatalog.current
        if let records = try container.decodeIfPresent([ModelInstallationRecord].self, forKey: .modelInstallationRecords) {
            modelInstallationRecords = catalog.mergedRecords(with: records)
        } else if let legacy = try container.decodeIfPresent(LegacyModelInstallState.self, forKey: .modelInstallState) {
            modelInstallationRecords = catalog.mergedRecords(with: [legacy.migratedRecord(for: catalog.defaultSelectionState.defaultModelID)])
        } else {
            modelInstallationRecords = catalog.defaultRecords()
        }

        let decodedSelection = try container.decodeIfPresent(ModelSelectionState.self, forKey: .modelSelectionState)
        modelSelectionState = decodedSelection ?? catalog.defaultSelectionState
        if catalog.descriptor(for: modelSelectionState.selectedModelID) == nil {
            modelSelectionState.selectedModelID = catalog.defaultSelectionState.defaultModelID
        }
        if catalog.descriptor(for: modelSelectionState.defaultModelID) == nil {
            modelSelectionState.defaultModelID = catalog.defaultSelectionState.defaultModelID
        }

        companionSettings.selectedCharacterID = CharacterCatalog.profile(for: companionSettings.selectedCharacterID).id
        companionSettings.selectedSceneID = CharacterCatalog.scene(
            for: companionSettings.selectedSceneID,
            characterID: companionSettings.selectedCharacterID
        ).id
        companionSettings.conversationLanguageID = LanguageCatalog.profile(for: companionSettings.conversationLanguageID).id
        companionSettings.explanationLanguageID = LanguageCatalog.profile(for: companionSettings.explanationLanguageID).id
        companionSettings.selectedVoiceBundleID = VoiceCatalog.bundle(
            for: companionSettings.selectedVoiceBundleID,
            characterID: companionSettings.selectedCharacterID,
            languageID: companionSettings.conversationLanguageID
        ).id
        companionSettings.allowChineseHints = companionSettings.explanationLanguageID != LanguageCatalog.english.id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(learnerProfile, forKey: .learnerProfile)
        try container.encode(companionSettings, forKey: .companionSettings)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(threadStates, forKey: .threadStates)
        try container.encode(vocabulary, forKey: .vocabulary)
        try container.encode(modelInstallationRecords, forKey: .modelInstallationRecords)
        try container.encode(modelSelectionState, forKey: .modelSelectionState)
    }

    static let `default` = MemorySnapshot(
        learnerProfile: .default,
        companionSettings: .default,
        sessions: [],
        threadStates: [],
        vocabulary: [],
        modelInstallationRecords: ModelCatalog.current.defaultRecords(),
        modelSelectionState: ModelCatalog.current.defaultSelectionState
    )
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array {
    var nonEmptyArray: [Element]? {
        isEmpty ? nil : self
    }
}

private extension FeedbackReport {
    var pronunciationTargetTokens: [String] {
        let tokens = pronunciationHighlights
            .joined(separator: " ")
            .components(separatedBy: CharacterSet.letters.inverted)
            .map { $0.lowercased() }
            .filter { $0.count >= 4 }
        return Array(tokens.orderedUnique().prefix(4))
    }
}

private extension Array where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

struct VoiceStyle: Equatable {
    var rate: Float
    var pitchMultiplier: Float
    var languageCode: String
    var voiceIdentifier: String?
    var prosodyPolicy: SpeechProsodyPolicy
    var accent: EnglishAccent

    static let `default` = VoiceStyle(
        rate: 0.47,
        pitchMultiplier: 1.02,
        languageCode: "en-US",
        voiceIdentifier: nil,
        prosodyPolicy: .chatWarm,
        accent: .american
    )
}

enum CallPhase: Equatable {
    case idle
    case preparing
    case listening
    case thinking
    case speaking
    case interrupted
    case finishing
    case error(String)
}

enum CharacterCatalog {
    static let primaryPortraitProfile = PortraitRenderProfile(
        id: "user-photo-main",
        sourceAssetName: "UserPortrait",
        cacheKey: "user-photo-main-v2",
        focusCrop: CGRect(x: 0.10, y: 0.02, width: 0.80, height: 0.94),
        headAnchor: CGPoint(x: 0.50, y: 0.22),
        eyeAnchors: [
            CGPoint(x: 0.35, y: 0.38),
            CGPoint(x: 0.65, y: 0.38)
        ],
        mouthRect: CGRect(x: 0.37, y: 0.60, width: 0.26, height: 0.14),
        shoulderLine: 0.86,
        parallaxTuning: PortraitParallaxTuning(
            backgroundDrift: 0.88,
            torsoDrift: 0.54,
            headDrift: 1.20,
            mouthDepth: 1.06,
            blinkDepth: 0.48
        ),
        lightingPreset: "portrait-soft-daylight",
        motionPreset: "human-video-call-natural"
    )

    static let flagship = CharacterProfile(
        id: "nova",
        displayName: "Mira",
        roleDescription: "A photo-driven AI speaking partner built for realistic video-call pacing, subtle expression, and local-first coaching.",
        defaultSceneID: "sunroom",
        animationResourceID: "nova-stage",
        defaultVoiceIdentifier: nil,
        speakingStyle: "Warm, direct, realistic, and restrained enough to feel like a real call instead of an animated avatar.",
        greetingStyle: "Starts like a real video call, not like a chatbot.",
        coachingEnergy: "high-touch",
        heroHeadline: "A local-first AI call that now leads with a photo-real video presence."
    )

    static let profiles: [CharacterProfile] = [
        flagship,
        CharacterProfile(
            id: "lyra",
            displayName: "Lyra",
            roleDescription: "A calm explainer who slows complex ideas down and helps the learner shape cleaner answers.",
            defaultSceneID: "study",
            animationResourceID: "lyra-stage",
            defaultVoiceIdentifier: nil,
            speakingStyle: "Measured, clear, reassuring, and detail-oriented.",
            greetingStyle: "Greets softly, then sets one focused direction.",
            coachingEnergy: "structured",
            heroHeadline: "Clearer answers, steadier rhythm, less pressure."
        ),
        CharacterProfile(
            id: "sol",
            displayName: "Sol",
            roleDescription: "An upbeat roleplay partner who pushes travel, social, and confidence-building speaking scenarios.",
            defaultSceneID: "nightcity",
            animationResourceID: "sol-stage",
            defaultVoiceIdentifier: nil,
            speakingStyle: "Energetic, encouraging, and expressive without becoming noisy.",
            greetingStyle: "Comes in with momentum and gives you an easy opening.",
            coachingEnergy: "energetic",
            heroHeadline: "Fast, vivid speaking practice with forward momentum."
        )
    ]

    static let scenes: [CharacterScene] = [
        CharacterScene(
            id: "sunroom",
            title: "Sunroom",
            ambienceDescription: "Warm daylight, clean glass, soft city depth.",
            backdropStyle: "soft-gradient-window",
            lightingStyle: "golden"
        ),
        CharacterScene(
            id: "study",
            title: "Study",
            ambienceDescription: "Quiet shelves, indirect light, focused atmosphere.",
            backdropStyle: "library-depth",
            lightingStyle: "neutral"
        ),
        CharacterScene(
            id: "nightcity",
            title: "Night City",
            ambienceDescription: "Blue hour skyline, soft reflections, cinematic contrast.",
            backdropStyle: "city-bokeh",
            lightingStyle: "neon"
        )
    ]

    static let packs: [CharacterPackManifest] = [
        CharacterPackManifest(
            characterID: "nova",
            sceneIDs: ["sunroom", "study", "nightcity"],
            animationResourceID: "nova-stage",
            fallbackArtworkID: "nova-fallback",
            lipSyncStyle: "soft-oval"
        ),
        CharacterPackManifest(
            characterID: "lyra",
            sceneIDs: ["study", "sunroom"],
            animationResourceID: "lyra-stage",
            fallbackArtworkID: "lyra-fallback",
            lipSyncStyle: "narrow-precise"
        ),
        CharacterPackManifest(
            characterID: "sol",
            sceneIDs: ["nightcity", "sunroom"],
            animationResourceID: "sol-stage",
            fallbackArtworkID: "sol-fallback",
            lipSyncStyle: "wide-bright"
        )
    ]
    static let bundles: [CharacterBundle] = [
        CharacterBundle(
            id: "nova-bundle",
            characterProfile: flagship,
            sceneIDs: ["sunroom", "study", "nightcity"],
            visualVariants: VideoCallVisualStyle.allCases,
            voiceBundleIDs: ["nova-voice", "narrator-voice"],
            openingPrompts: [
                "Open like a real video call and keep the first turn warm.",
                "Default to fast turn-taking and easy interruption."
            ],
            memoryTone: "Tracks continuity like a familiar conversation partner.",
            fallbackArtworkID: "nova-fallback",
            renderRuntimeKind: .photoPseudo3D,
            portraitProfileID: primaryPortraitProfile.id,
            isReleaseReady: true,
            lipSyncStrategy: "timeline-heuristic",
            speechAnimationTuning: "photo-pseudo3d-natural",
            releaseTier: .flagship
        ),
        CharacterBundle(
            id: "lyra-bundle",
            characterProfile: profiles[1],
            sceneIDs: ["study", "sunroom"],
            visualVariants: VideoCallVisualStyle.allCases,
            voiceBundleIDs: ["lyra-voice", "narrator-voice"],
            openingPrompts: [
                "Start calmer and keep one clear objective in view.",
                "Bias toward explanation-heavy turns when needed."
            ],
            memoryTone: "Keeps structured notes about what the learner is trying to improve.",
            fallbackArtworkID: "lyra-fallback",
            renderRuntimeKind: .legacyFallback,
            portraitProfileID: nil,
            isReleaseReady: false,
            lipSyncStrategy: "energy-driven",
            speechAnimationTuning: "legacy-fallback",
            releaseTier: .future
        ),
        CharacterBundle(
            id: "sol-bundle",
            characterProfile: profiles[2],
            sceneIDs: ["nightcity", "sunroom"],
            visualVariants: VideoCallVisualStyle.allCases,
            voiceBundleIDs: ["sol-voice", "coach-voice"],
            openingPrompts: [
                "Open with momentum and a practical situation quickly.",
                "Make roleplay and challenge formats feel energetic."
            ],
            memoryTone: "Carries forward confidence wins and reusable phrases.",
            fallbackArtworkID: "sol-fallback",
            renderRuntimeKind: .legacyFallback,
            portraitProfileID: nil,
            isReleaseReady: false,
            lipSyncStrategy: "energy-driven",
            speechAnimationTuning: "legacy-fallback",
            releaseTier: .future
        )
    ]

    static var portraitProfiles: [PortraitRenderProfile] {
        [primaryPortraitProfile]
    }

    static var primaryPortraitAvailable: Bool {
        portraitVariantAvailable
    }

    static var selectableProfiles: [CharacterProfile] {
        if primaryPortraitAvailable {
            let ready = bundles
                .filter(\.isReleaseReady)
                .map(\.characterProfile)
            return ready.isEmpty ? [flagship] : ready
        }
        return profiles
    }

    static func profile(for id: String?) -> CharacterProfile {
        guard let id else { return flagship }
        return selectableProfiles.first(where: { $0.id == id }) ?? flagship
    }

    static func pack(for characterID: String?) -> CharacterPackManifest {
        let characterID = profile(for: characterID).id
        return packs.first(where: { $0.characterID == characterID }) ?? packs[0]
    }

    static func bundle(for characterID: String?) -> CharacterBundle {
        let characterID = profile(for: characterID).id
        return bundles.first(where: { $0.characterProfile.id == characterID }) ?? bundles[0]
    }

    static func portraitProfile(for id: String?) -> PortraitRenderProfile? {
        guard let id else { return nil }
        return portraitProfiles.first(where: { $0.id == id })
    }

    static func defaultScene(for characterID: String?) -> CharacterScene {
        let profile = profile(for: characterID)
        return scenes.first(where: { $0.id == profile.defaultSceneID }) ?? scenes[0]
    }

    static func scene(for id: String?, characterID: String? = nil) -> CharacterScene {
        let pack = pack(for: characterID)
        if let id, pack.sceneIDs.contains(id), let scene = scenes.first(where: { $0.id == id }) {
            return scene
        }
        return defaultScene(for: characterID)
    }

    static func availableScenes(for characterID: String?) -> [CharacterScene] {
        let pack = pack(for: characterID)
        let mapped = pack.sceneIDs.compactMap { sceneID in
            scenes.first(where: { $0.id == sceneID })
        }
        return mapped.isEmpty ? [defaultScene(for: characterID)] : mapped
    }

    static var portraitVariantAvailable: Bool {
        hasBundledPortraitAsset
    }

    private static var hasBundledPortraitAsset: Bool {
        for name in ["UserPortrait", "myself"] {
            if Bundle.main.url(forResource: name, withExtension: "jpg") != nil {
                return true
            }
            if Bundle.main.url(forResource: name, withExtension: "jpeg") != nil {
                return true
            }
        }
        return false
    }
}

enum LanguageCatalog {
    static let english = LanguageProfile(
        id: "english",
        displayName: "English",
        conversationLanguage: "English",
        explanationLanguage: "English",
        asrLocale: "en-US",
        ttsLanguageCode: "en-US",
        ttsVoiceSet: ["nova-voice", "lyra-voice", "michael-voice", "george-voice"],
        bundledASRModelID: "sherpa-onnx-en-us-streaming",
        bundledTTSModelID: "kokoro-multi-lang-v1_0",
        supportsTutor: true,
        supportsPronunciationDrill: true,
        supportsSpeechConversation: true,
        supportsChineseExplanationText: true
    )

    static let simplifiedChinese = LanguageProfile(
        id: "chinese",
        displayName: "Chinese",
        conversationLanguage: "Chinese",
        explanationLanguage: "Simplified Chinese",
        asrLocale: "zh-CN",
        ttsLanguageCode: "zh-CN",
        ttsVoiceSet: ["multilingual-voice"],
        bundledASRModelID: nil,
        bundledTTSModelID: nil,
        supportsTutor: true,
        supportsPronunciationDrill: false,
        supportsSpeechConversation: false,
        supportsChineseExplanationText: true
    )

    static let japanese = LanguageProfile(
        id: "japanese",
        displayName: "Japanese",
        conversationLanguage: "Japanese",
        explanationLanguage: "Japanese",
        asrLocale: "ja-JP",
        ttsLanguageCode: "ja-JP",
        ttsVoiceSet: ["multilingual-voice"],
        bundledASRModelID: nil,
        bundledTTSModelID: nil,
        supportsTutor: true,
        supportsPronunciationDrill: false,
        supportsSpeechConversation: false,
        supportsChineseExplanationText: false
    )

    static let korean = LanguageProfile(
        id: "korean",
        displayName: "Korean",
        conversationLanguage: "Korean",
        explanationLanguage: "Korean",
        asrLocale: "ko-KR",
        ttsLanguageCode: "ko-KR",
        ttsVoiceSet: ["multilingual-voice"],
        bundledASRModelID: nil,
        bundledTTSModelID: nil,
        supportsTutor: true,
        supportsPronunciationDrill: false,
        supportsSpeechConversation: false,
        supportsChineseExplanationText: false
    )

    static let spanish = LanguageProfile(
        id: "spanish",
        displayName: "Spanish",
        conversationLanguage: "Spanish",
        explanationLanguage: "Spanish",
        asrLocale: "es-ES",
        ttsLanguageCode: "es-ES",
        ttsVoiceSet: ["multilingual-voice"],
        bundledASRModelID: nil,
        bundledTTSModelID: nil,
        supportsTutor: true,
        supportsPronunciationDrill: false,
        supportsSpeechConversation: false,
        supportsChineseExplanationText: false
    )

    static let french = LanguageProfile(
        id: "french",
        displayName: "French",
        conversationLanguage: "French",
        explanationLanguage: "French",
        asrLocale: "fr-FR",
        ttsLanguageCode: "fr-FR",
        ttsVoiceSet: ["multilingual-voice"],
        bundledASRModelID: nil,
        bundledTTSModelID: nil,
        supportsTutor: true,
        supportsPronunciationDrill: false,
        supportsSpeechConversation: false,
        supportsChineseExplanationText: false
    )

    static let german = LanguageProfile(
        id: "german",
        displayName: "German",
        conversationLanguage: "German",
        explanationLanguage: "German",
        asrLocale: "de-DE",
        ttsLanguageCode: "de-DE",
        ttsVoiceSet: ["multilingual-voice"],
        bundledASRModelID: nil,
        bundledTTSModelID: nil,
        supportsTutor: true,
        supportsPronunciationDrill: false,
        supportsSpeechConversation: false,
        supportsChineseExplanationText: false
    )

    static let all: [LanguageProfile] = [
        english,
        simplifiedChinese,
        japanese,
        korean,
        spanish,
        french,
        german
    ]

    static func profile(for id: String?) -> LanguageProfile {
        guard let id else { return english }
        return all.first(where: { $0.id == id }) ?? english
    }
}

enum VoiceCatalog {
    static let bundles: [VoiceBundle] = [
        VoiceBundle(
            id: "nova-voice",
            displayName: "American Female",
            characterID: CharacterCatalog.flagship.id,
            languageProfileID: LanguageCatalog.english.id,
            voiceIdentifier: nil,
            languageCode: "en-US",
            pitchMultiplier: 1.04,
            rateMultiplier: 1.0,
            styleDescription: "Clear American English with a warm, teaching-friendly delivery.",
            accent: .american,
            genderPresentation: .female,
            ttsModelFamily: .kokoro,
            localVoiceAssetID: "kokoro-multi-lang-v1_0",
            runtimeVoiceID: "kokoro-multi-lang-v1_0",
            runtimeSpeakerKey: "af_nova",
            runtimeSpeakerID: 7,
            pronunciationLexiconID: EnglishAccent.american.pronunciationLexiconID,
            emotionPreset: .warm,
            prosodyPolicy: .chatWarm,
            chunkingPolicy: .adaptive,
            prewarmRequired: true,
            isUserVisible: true,
            isReleaseReady: true
        ),
        VoiceBundle(
            id: "lyra-voice",
            displayName: "British Female",
            characterID: CharacterCatalog.flagship.id,
            languageProfileID: LanguageCatalog.english.id,
            voiceIdentifier: nil,
            languageCode: "en-GB",
            pitchMultiplier: 0.98,
            rateMultiplier: 0.95,
            styleDescription: "Clear British English with steadier tutor-style phrasing.",
            accent: .british,
            genderPresentation: .female,
            ttsModelFamily: .kokoro,
            localVoiceAssetID: "kokoro-multi-lang-v1_0",
            runtimeVoiceID: "kokoro-multi-lang-v1_0",
            runtimeSpeakerKey: "bf_emma",
            runtimeSpeakerID: 21,
            pronunciationLexiconID: EnglishAccent.british.pronunciationLexiconID,
            emotionPreset: .tutorFocused,
            prosodyPolicy: .tutorClearUK,
            chunkingPolicy: .sentence,
            prewarmRequired: true,
            isUserVisible: true,
            isReleaseReady: true
        ),
        VoiceBundle(
            id: "michael-voice",
            displayName: "American Male",
            characterID: nil,
            languageProfileID: LanguageCatalog.english.id,
            voiceIdentifier: nil,
            languageCode: "en-US",
            pitchMultiplier: 0.94,
            rateMultiplier: 0.98,
            styleDescription: "American English male reference voice, staged for future character bundles.",
            accent: .american,
            genderPresentation: .male,
            ttsModelFamily: .kokoro,
            localVoiceAssetID: "kokoro-multi-lang-v1_0",
            runtimeVoiceID: "kokoro-multi-lang-v1_0",
            runtimeSpeakerKey: "am_michael",
            runtimeSpeakerID: 16,
            pronunciationLexiconID: EnglishAccent.american.pronunciationLexiconID,
            emotionPreset: .neutral,
            prosodyPolicy: .chatBright,
            chunkingPolicy: .adaptive,
            prewarmRequired: true,
            isUserVisible: false,
            isReleaseReady: true
        ),
        VoiceBundle(
            id: "george-voice",
            displayName: "British Male",
            characterID: nil,
            languageProfileID: LanguageCatalog.english.id,
            voiceIdentifier: nil,
            languageCode: "en-GB",
            pitchMultiplier: 0.92,
            rateMultiplier: 0.96,
            styleDescription: "British English male reference voice, staged for future character bundles.",
            accent: .british,
            genderPresentation: .male,
            ttsModelFamily: .kokoro,
            localVoiceAssetID: "kokoro-multi-lang-v1_0",
            runtimeVoiceID: "kokoro-multi-lang-v1_0",
            runtimeSpeakerKey: "bm_george",
            runtimeSpeakerID: 26,
            pronunciationLexiconID: EnglishAccent.british.pronunciationLexiconID,
            emotionPreset: .tutorFocused,
            prosodyPolicy: .tutorClearUK,
            chunkingPolicy: .sentence,
            prewarmRequired: true,
            isUserVisible: false,
            isReleaseReady: true
        ),
        VoiceBundle(
            id: "multilingual-voice",
            displayName: "Multilingual Fallback",
            characterID: nil,
            languageProfileID: LanguageCatalog.english.id,
            voiceIdentifier: nil,
            languageCode: "en-US",
            pitchMultiplier: 1.0,
            rateMultiplier: 1.0,
            styleDescription: "Falls back to system voices for non-English routing.",
            accent: .american,
            genderPresentation: .female,
            ttsModelFamily: .piperLegacy,
            localVoiceAssetID: "system-tts-multilingual",
            runtimeVoiceID: "system-tts-multilingual",
            emotionPreset: .neutral,
            prosodyPolicy: .chatWarm,
            chunkingPolicy: .sentence,
            isUserVisible: false,
            isReleaseReady: false
        )
    ]

    static func bundles(for characterID: String?, languageID: String?) -> [VoiceBundle] {
        matchingBundles(for: characterID, languageID: languageID, includeHidden: false)
    }

    private static func matchingBundles(
        for characterID: String?,
        languageID: String?,
        includeHidden: Bool
    ) -> [VoiceBundle] {
        let resolvedLanguage = LanguageCatalog.profile(for: languageID)
        let preferredCharacterID = CharacterCatalog.profile(for: characterID).id
        let matchingLanguage = bundles.filter {
            $0.languageProfileID == resolvedLanguage.id || resolvedLanguage.ttsVoiceSet.contains($0.id)
        }
        let characterSpecific = matchingLanguage.filter { $0.characterID == preferredCharacterID }
        let generic = matchingLanguage.filter { $0.characterID == nil }
        let ordered = characterSpecific + generic
        guard ordered.isEmpty == false else { return bundles }

        let releaseScoped: [VoiceBundle]
        if CharacterCatalog.primaryPortraitAvailable {
            let releaseReady = ordered.filter(\.isReleaseReady)
            releaseScoped = releaseReady.isEmpty ? ordered : releaseReady
        } else {
            releaseScoped = ordered
        }

        if includeHidden {
            return releaseScoped
        }

        let visible = releaseScoped.filter(\.isUserVisible)
        return visible.isEmpty ? releaseScoped : visible
    }

    static func bundle(for id: String?, characterID: String?, languageID: String?) -> VoiceBundle {
        if let id {
            let allowed = matchingBundles(for: characterID, languageID: languageID, includeHidden: true)
            if let matched = allowed.first(where: { $0.id == id }) {
                return matched
            }
            if let matched = bundles.first(where: { $0.id == id }), CharacterCatalog.primaryPortraitAvailable == false {
                return matched
            }
        }
        return defaultBundle(for: characterID, languageID: languageID)
    }

    static func releaseRuntimeBundle(for characterID: String?, languageID: String?) -> VoiceBundle {
        let available = matchingBundles(for: characterID, languageID: languageID, includeHidden: false)
        if let bundled = available.first(where: { $0.ttsModelFamily == .kokoro }) {
            return bundled
        }
        if let matched = bundles.first(where: { $0.isReleaseReady && $0.isUserVisible }) {
            return matched
        }
        return available.first ?? bundles[0]
    }

    static func defaultBundle(for characterID: String?, languageID: String?) -> VoiceBundle {
        releaseRuntimeBundle(for: characterID, languageID: languageID)
    }
}

enum ScenarioCatalog {
    static let chatPresets: [ScenarioPreset] = [
        ScenarioPreset(
            id: "daily-checkin",
            category: .freeTalk,
            title: "Daily Check-in",
            summary: "A natural catch-up call about today, mood, and one small story.",
            openingGoal: "Open with one warm sentence and ask about the learner's day.",
            followUpHint: "Push for one extra detail or one reason without sounding formal.",
            suggestedReplyLength: "2 short spoken chunks",
            preferredMode: .chat
        ),
        ScenarioPreset(
            id: "weekend-plans",
            category: .freeTalk,
            title: "Weekend Plans",
            summary: "Easy conversation about plans, preferences, and habits.",
            openingGoal: "Get the learner describing a plan they actually care about.",
            followUpHint: "Invite a comparison or preference to extend the answer.",
            suggestedReplyLength: "2-3 short spoken chunks",
            preferredMode: .chat
        ),
        ScenarioPreset(
            id: "lecture-explainer",
            category: .lectureStyleExplanation,
            title: "Lecture-style Explainer",
            summary: "Ask the companion to explain one topic slowly, then paraphrase it back.",
            openingGoal: "Explain one practical topic clearly, then check what the learner understood.",
            followUpHint: "Prompt the learner to restate the idea in simpler words.",
            suggestedReplyLength: "1 explanation + 1 paraphrase",
            preferredMode: .chat
        ),
        ScenarioPreset(
            id: "theme-challenge",
            category: .gameThemeChallenge,
            title: "Theme Challenge",
            summary: "Keep the call moving while the learner must stay inside one playful topic.",
            openingGoal: "Launch a narrow theme and keep follow-ups fast and vivid.",
            followUpHint: "Ask for one surprising detail or one quick comparison.",
            suggestedReplyLength: "Short fast turns",
            preferredMode: .chat
        )
    ]

    static let tutorPresets: [ScenarioPreset] = [
        ScenarioPreset(
            id: "clarify-an-opinion",
            category: .lectureStyleExplanation,
            title: "Clarify an Opinion",
            summary: "Push one opinion into a clearer answer with a reason and example.",
            openingGoal: "Ask for one opinion, then require one reason and one example.",
            followUpHint: "If the learner is too short, ask them to restate more clearly.",
            suggestedReplyLength: "1 focused answer with 3 beats",
            preferredMode: .tutor
        ),
        ScenarioPreset(
            id: "travel-roleplay",
            category: .roleplayPractice,
            title: "Travel Roleplay",
            summary: "Practice practical travel English with specific goals and constraints.",
            openingGoal: "Drop the learner into a simple travel situation immediately.",
            followUpHint: "Prompt for a clearer request, then a polite follow-up sentence.",
            suggestedReplyLength: "1 concise roleplay reply at a time",
            preferredMode: .tutor
        ),
        ScenarioPreset(
            id: "pronunciation-loop",
            category: .pronunciationDrill,
            title: "Pronunciation Loop",
            summary: "Repeat a target phrase, tighten one sound, then reuse it in a longer sentence.",
            openingGoal: "Pick one phrase and coach the learner through a cleaner repeat.",
            followUpHint: "Highlight one word that needs slower stress or a clearer consonant.",
            suggestedReplyLength: "1 short phrase at a time",
            preferredMode: .tutor
        ),
        ScenarioPreset(
            id: "vocabulary-carry-over",
            category: .vocabularyCarryOver,
            title: "Vocabulary Carry-over",
            summary: "Bring back saved words from the last call and force them into new examples.",
            openingGoal: "Start with one saved word and ask the learner to reuse it naturally.",
            followUpHint: "Push the learner to reuse the same word in a different context.",
            suggestedReplyLength: "1 sentence + 1 retry",
            preferredMode: .tutor
        )
    ]

    static func presets(for mode: ConversationMode) -> [ScenarioPreset] {
        switch mode {
        case .chat:
            return chatPresets
        case .tutor:
            return tutorPresets
        }
    }

    static func recommended(for learner: LearnerProfile, mode: ConversationMode) -> ScenarioPreset {
        let goal = learner.learningGoal.lowercased()
        if mode == .tutor, goal.contains("travel") {
            return tutorPresets.first(where: { $0.id == "travel-roleplay" }) ?? tutorPresets[0]
        }
        if mode == .tutor {
            return tutorPresets[0]
        }
        if goal.contains("weekend") || goal.contains("daily") {
            return chatPresets.first(where: { $0.id == "weekend-plans" }) ?? chatPresets[0]
        }
        return chatPresets[0]
    }

    static func preset(for id: String?, mode: ConversationMode) -> ScenarioPreset {
        guard let id else { return recommended(for: .default, mode: mode) }
        return presets(for: mode).first(where: { $0.id == id }) ?? recommended(for: .default, mode: mode)
    }
}

extension ConversationSession {
    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }
}

extension VoiceBundle {
    var accentLabel: String {
        accent.displayName
    }

    var selectionLabel: String {
        "\(accent.shortLabel) \(genderPresentation.displayName)"
    }
}
