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

enum InferenceBackendPreference: String, Codable, CaseIterable, Identifiable {
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

enum AvatarState: String, Codable {
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

struct CharacterPackManifest: Codable, Equatable, Hashable {
    var characterID: String
    var sceneIDs: [String]
    var animationResourceID: String
    var fallbackArtworkID: String
    var lipSyncStyle: String
}

struct CompanionSettings: Codable, Equatable {
    var selectedCharacterID: String
    var selectedSceneID: String
    var speechRate: Float
    var allowChineseHints: Bool
    var backendPreference: InferenceBackendPreference
    var preferredVoiceIdentifier: String?
    var warmupCompleted: Bool

    static let `default` = CompanionSettings(
        selectedCharacterID: CharacterCatalog.flagship.id,
        selectedSceneID: CharacterCatalog.flagship.defaultSceneID,
        speechRate: 0.47,
        allowChineseHints: true,
        backendPreference: .gpu,
        preferredVoiceIdentifier: nil,
        warmupCompleted: false
    )
}

struct ScenarioPreset: Codable, Equatable, Hashable, Identifiable {
    let id: String
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
}

struct SubtitleOverlayState: Equatable {
    var mode: SubtitleOverlayMode = .collapsed
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
    var goalCompletionSummary: String
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
        goalCompletionSummary: String = "This session created a solid next step for your speaking practice.",
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
        self.goalCompletionSummary = goalCompletionSummary
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
        case goalCompletionSummary
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
        goalCompletionSummary = try container.decodeIfPresent(String.self, forKey: .goalCompletionSummary) ?? "This session created a solid next step for your speaking practice."
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
    var sceneID: String
    var scenarioID: String?
    var learningPlanSnapshot: LearningFocusPlan?

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
        sceneID: String = CharacterCatalog.flagship.defaultSceneID,
        scenarioID: String? = nil,
        learningPlanSnapshot: LearningFocusPlan? = nil
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
        self.sceneID = sceneID
        self.scenarioID = scenarioID
        self.learningPlanSnapshot = learningPlanSnapshot
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
        case sceneID
        case scenarioID
        case learningPlanSnapshot
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
        let defaultSceneID = CharacterCatalog.defaultScene(for: characterID).id
        sceneID = try container.decodeIfPresent(String.self, forKey: .sceneID) ?? defaultSceneID
        scenarioID = try container.decodeIfPresent(String.self, forKey: .scenarioID)
        learningPlanSnapshot = try container.decodeIfPresent(LearningFocusPlan.self, forKey: .learningPlanSnapshot)
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
    var vocabulary: [VocabularyItem]
    var modelInstallationRecords: [ModelInstallationRecord]
    var modelSelectionState: ModelSelectionState

    init(
        learnerProfile: LearnerProfile,
        companionSettings: CompanionSettings,
        sessions: [ConversationSession],
        vocabulary: [VocabularyItem],
        modelInstallationRecords: [ModelInstallationRecord],
        modelSelectionState: ModelSelectionState
    ) {
        self.learnerProfile = learnerProfile
        self.companionSettings = companionSettings
        self.sessions = sessions
        self.vocabulary = vocabulary
        self.modelInstallationRecords = modelInstallationRecords
        self.modelSelectionState = modelSelectionState
    }

    private enum CodingKeys: String, CodingKey {
        case learnerProfile
        case companionSettings
        case sessions
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
        vocabulary = try container.decodeIfPresent([VocabularyItem].self, forKey: .vocabulary) ?? []

        if let settings = try container.decodeIfPresent(CompanionSettings.self, forKey: .companionSettings) {
            companionSettings = settings
        } else if let legacyPersona = try container.decodeIfPresent(LegacyPersonaState.self, forKey: .personaState) {
            companionSettings = CompanionSettings(
                selectedCharacterID: CharacterCatalog.flagship.id,
                selectedSceneID: CharacterCatalog.flagship.defaultSceneID,
                speechRate: legacyPersona.speechRate,
                allowChineseHints: legacyPersona.allowChineseHints,
                backendPreference: legacyPersona.backendPreference,
                preferredVoiceIdentifier: legacyPersona.preferredVoiceIdentifier,
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(learnerProfile, forKey: .learnerProfile)
        try container.encode(companionSettings, forKey: .companionSettings)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(vocabulary, forKey: .vocabulary)
        try container.encode(modelInstallationRecords, forKey: .modelInstallationRecords)
        try container.encode(modelSelectionState, forKey: .modelSelectionState)
    }

    static let `default` = MemorySnapshot(
        learnerProfile: .default,
        companionSettings: .default,
        sessions: [],
        vocabulary: [],
        modelInstallationRecords: ModelCatalog.current.defaultRecords(),
        modelSelectionState: ModelCatalog.current.defaultSelectionState
    )
}

struct VoiceStyle: Equatable {
    var rate: Float
    var pitchMultiplier: Float
    var languageCode: String

    static let `default` = VoiceStyle(rate: 0.47, pitchMultiplier: 1.02, languageCode: "en-US")
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
    static let flagship = CharacterProfile(
        id: "nova",
        displayName: "Nova",
        roleDescription: "A poised AI speaking partner who feels present on a call, keeps your confidence up, and still coaches precisely when it matters.",
        defaultSceneID: "sunroom",
        animationResourceID: "nova-stage",
        defaultVoiceIdentifier: nil,
        speakingStyle: "Warm, direct, lightly playful, quick to keep the call moving.",
        greetingStyle: "Starts like a real video call, not like a chatbot.",
        coachingEnergy: "high-touch",
        heroHeadline: "Video-call English practice that feels human."
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
            sceneIDs: ["sunroom", "study"],
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

    static func profile(for id: String?) -> CharacterProfile {
        guard let id else { return flagship }
        return profiles.first(where: { $0.id == id }) ?? flagship
    }

    static func pack(for characterID: String?) -> CharacterPackManifest {
        let characterID = profile(for: characterID).id
        return packs.first(where: { $0.characterID == characterID }) ?? packs[0]
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
}

enum ScenarioCatalog {
    static let chatPresets: [ScenarioPreset] = [
        ScenarioPreset(
            id: "daily-checkin",
            title: "Daily Check-in",
            summary: "A natural catch-up call about today, mood, and one small story.",
            openingGoal: "Open with one warm sentence and ask about the learner's day.",
            followUpHint: "Push for one extra detail or one reason without sounding formal.",
            suggestedReplyLength: "2 short spoken chunks",
            preferredMode: .chat
        ),
        ScenarioPreset(
            id: "weekend-plans",
            title: "Weekend Plans",
            summary: "Easy conversation about plans, preferences, and habits.",
            openingGoal: "Get the learner describing a plan they actually care about.",
            followUpHint: "Invite a comparison or preference to extend the answer.",
            suggestedReplyLength: "2-3 short spoken chunks",
            preferredMode: .chat
        )
    ]

    static let tutorPresets: [ScenarioPreset] = [
        ScenarioPreset(
            id: "clarify-an-opinion",
            title: "Clarify an Opinion",
            summary: "Push one opinion into a clearer answer with a reason and example.",
            openingGoal: "Ask for one opinion, then require one reason and one example.",
            followUpHint: "If the learner is too short, ask them to restate more clearly.",
            suggestedReplyLength: "1 focused answer with 3 beats",
            preferredMode: .tutor
        ),
        ScenarioPreset(
            id: "travel-roleplay",
            title: "Travel Roleplay",
            summary: "Practice practical travel English with specific goals and constraints.",
            openingGoal: "Drop the learner into a simple travel situation immediately.",
            followUpHint: "Prompt for a clearer request, then a polite follow-up sentence.",
            suggestedReplyLength: "1 concise roleplay reply at a time",
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
