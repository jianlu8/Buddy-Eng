import Foundation

actor FileMemoryStore: MemoryStore {
    private let filesystem: AppFilesystem
    private let userDataStore: UserDataStore
    private let modelStateStore: ModelStateStore
    private let assetStateStore: AssetStateStore
    private let persistenceCoordinator: PersistenceCoordinator
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var snapshot: MemorySnapshot

    init(filesystem: AppFilesystem) {
        self.filesystem = filesystem
        let userDataStore = UserDataStore(filesystem: filesystem)
        let modelStateStore = ModelStateStore(filesystem: filesystem)
        let assetStateStore = AssetStateStore(filesystem: filesystem)
        self.userDataStore = userDataStore
        self.modelStateStore = modelStateStore
        self.assetStateStore = assetStateStore
        self.persistenceCoordinator = PersistenceCoordinator(
            filesystem: filesystem,
            userDataStore: userDataStore,
            modelStateStore: modelStateStore,
            assetStateStore: assetStateStore
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.snapshot = .default
    }

    func load() async throws {
        snapshot = try await persistenceCoordinator.loadMemorySnapshot()
    }

    func fetchSnapshot() -> MemorySnapshot {
        snapshot
    }

    func fetchPersonaSummary() -> String {
        let profile = snapshot.learnerProfile
        let settings = snapshot.companionSettings
        let character = CharacterCatalog.profile(for: settings.selectedCharacterID)
        let scene = CharacterCatalog.scene(for: settings.selectedSceneID, characterID: character.id)
        let conversationLanguage = LanguageCatalog.profile(for: settings.conversationLanguageID)
        let explanationLanguage = LanguageCatalog.profile(for: settings.explanationLanguageID)
        let voiceBundle = VoiceCatalog.bundle(
            for: settings.selectedVoiceBundleID,
            characterID: settings.selectedCharacterID,
            languageID: settings.conversationLanguageID
        )
        let topics = profile.favoriteTopics.prefix(3).joined(separator: ", ")
        let mistakes = profile.commonMistakes.prefix(3).joined(separator: ", ")
        return """
        Learner: \(profile.preferredName.isEmpty ? "Anonymous" : profile.preferredName)
        Goal: \(profile.learningGoal.isEmpty ? "Speak more confidently in everyday English." : profile.learningGoal)
        CEFR: \(profile.cefrEstimate.rawValue)
        Character: \(character.displayName), scene=\(scene.title), visualStyle=\(settings.visualStyle.rawValue), voice=\(voiceBundle.displayName), conversationLanguage=\(conversationLanguage.displayName), explanationLanguage=\(explanationLanguage.displayName), portraitMode=\(settings.portraitModeEnabled ? "on" : "off"), speechRate=\(settings.speechRate), performanceTier=\(settings.performanceTier.rawValue)
        Topics: \(topics.isEmpty ? "daily life, travel, work" : topics)
        Common mistakes: \(mistakes.isEmpty ? "none collected yet" : mistakes)
        """
    }

    func fetchLearningContext() -> String {
        let recentThreads = snapshot.threadStates.sorted { $0.updatedAt > $1.updatedAt }.prefix(3)
        guard recentThreads.isEmpty == false else { return "No previous sessions yet." }

        return recentThreads.compactMap { thread in
            guard let session = snapshot.sessions.first(where: { $0.id == thread.latestSessionID }) else { return nil }
            let character = CharacterCatalog.profile(for: thread.characterID)
            let scenario = thread.scenarioID.flatMap { ScenarioCatalog.preset(for: $0, mode: thread.mode).title } ?? "Open Conversation"
            let language = LanguageCatalog.profile(for: thread.languageProfileID).displayName
            let highlights = session.keyMoments.prefix(2).joined(separator: "; ")
            return "[\(thread.mode.title)] \(character.displayName) • \(scenario) • \(language) • thread=\(thread.id) • mission=\(thread.nextMission) • summary=\(thread.summary) Highlights: \(highlights)"
        }.joined(separator: "\n")
    }

    func saveTurn(_ turn: ConversationTurn, sessionID: UUID) async throws {
        guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        snapshot.sessions[index].turns.append(turn)
        try absorbVocabulary(from: turn)
        try await persist()
    }

    func saveSessionFeedback(_ feedback: FeedbackReport, sessionID: UUID) async throws {
        guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        snapshot.sessions[index].feedbackReport = feedback
        upsertThreadState(from: snapshot.sessions[index])
        let newMistakes = feedback.grammarIssues.map(\.source) + feedback.pronunciationTips.map(\.source)
        snapshot.learnerProfile.commonMistakes = Array((newMistakes + snapshot.learnerProfile.commonMistakes).orderedUnique().prefix(8))
        if feedback.carryOverVocabulary.isEmpty == false {
            mergeCarryOverVocabulary(feedback.carryOverVocabulary)
        }
        snapshot.learnerProfile.updatedAt = .now
        try await persist()
    }

    func upsertSession(_ session: ConversationSession) async throws {
        if let index = snapshot.sessions.firstIndex(where: { $0.id == session.id }) {
            snapshot.sessions[index] = session
            upsertThreadState(from: snapshot.sessions[index])
        } else {
            snapshot.sessions.insert(session, at: 0)
            upsertThreadState(from: session)
        }
        snapshot.learnerProfile.firstSessionAt = snapshot.learnerProfile.firstSessionAt ?? session.startedAt
        snapshot.learnerProfile.cefrEstimate = estimateCEFR(from: snapshot.sessions)
        snapshot.learnerProfile.updatedAt = .now
        try await persist()
    }

    func updateLearnerProfile(_ mutate: @Sendable (inout LearnerProfile) -> Void) async throws {
        mutate(&snapshot.learnerProfile)
        snapshot.learnerProfile.updatedAt = .now
        try await persist()
    }

    func updateCompanionSettings(_ mutate: @Sendable (inout CompanionSettings) -> Void) async throws {
        mutate(&snapshot.companionSettings)
        snapshot.companionSettings.selectedCharacterID = CharacterCatalog.profile(for: snapshot.companionSettings.selectedCharacterID).id
        snapshot.companionSettings.selectedSceneID = CharacterCatalog.scene(
            for: snapshot.companionSettings.selectedSceneID,
            characterID: snapshot.companionSettings.selectedCharacterID
        ).id
        snapshot.companionSettings.conversationLanguageID = LanguageCatalog.profile(for: snapshot.companionSettings.conversationLanguageID).id
        snapshot.companionSettings.explanationLanguageID = LanguageCatalog.profile(for: snapshot.companionSettings.explanationLanguageID).id
        snapshot.companionSettings.selectedVoiceBundleID = VoiceCatalog.bundle(
            for: snapshot.companionSettings.selectedVoiceBundleID,
            characterID: snapshot.companionSettings.selectedCharacterID,
            languageID: snapshot.companionSettings.conversationLanguageID
        ).id
        snapshot.companionSettings.allowChineseHints = snapshot.companionSettings.explanationLanguageID != LanguageCatalog.english.id
        snapshot.companionSettings.portraitModeEnabled = CharacterCatalog.primaryPortraitAvailable
        try await persist()
    }

    func upsertVocabulary(_ vocabulary: [VocabularyItem]) async throws {
        var dictionary = Dictionary(uniqueKeysWithValues: snapshot.vocabulary.map { ($0.term.lowercased(), $0) })
        for item in vocabulary {
            dictionary[item.term.lowercased()] = item
        }
        snapshot.vocabulary = dictionary.values.sorted { $0.updatedAt > $1.updatedAt }
        try await persist()
    }

    func deleteAllMemory() async throws {
        snapshot = .default
        try await persist()
    }

    func updateModelCatalogState(records: [ModelInstallationRecord], selectionState: ModelSelectionState) async throws {
        snapshot.modelInstallationRecords = ModelCatalog.current.mergedRecords(with: records)
        snapshot.modelSelectionState = selectionState
        try await persist()
    }

    func updateModelSelectionState(_ selectionState: ModelSelectionState) async throws {
        snapshot.modelSelectionState = selectionState
        try await persist()
    }

    func updateModelInstallationRecord(_ record: ModelInstallationRecord) async throws {
        var recordsByID = Dictionary(uniqueKeysWithValues: snapshot.modelInstallationRecords.map { ($0.modelID, $0) })
        recordsByID[record.modelID] = record
        snapshot.modelInstallationRecords = ModelCatalog.current.mergedRecords(with: Array(recordsByID.values))
        try await persist()
    }

    private func persist() async throws {
        try await persistenceCoordinator.persist(memorySnapshot: snapshot)
    }

    private func estimateCEFR(from sessions: [ConversationSession]) -> CEFRLevel {
        let userTurns = sessions.flatMap(\.turns).filter { $0.role == .user }
        let averageWords = userTurns.isEmpty ? 6 : userTurns.map { $0.text.split(whereSeparator: \.isWhitespace).count }.reduce(0, +) / userTurns.count
        let correctionCount = userTurns.flatMap(\.corrections).count
        switch (averageWords, correctionCount) {
        case (0...5, _):
            return .a1
        case (6...9, _):
            return .a2
        case (10...14, 0...4):
            return .b1
        case (15...24, 0...6):
            return .b2
        default:
            return .c1
        }
    }

    private func absorbVocabulary(from turn: ConversationTurn) throws {
        guard turn.role == .assistant else { return }
        let candidates = turn.text
            .components(separatedBy: CharacterSet.letters.inverted)
            .map { $0.lowercased() }
            .filter { $0.count >= 6 }
        guard candidates.isEmpty == false else { return }

        let existing = Dictionary(uniqueKeysWithValues: snapshot.vocabulary.map { ($0.term.lowercased(), $0) })
        let additions = candidates.prefix(2).compactMap { word -> VocabularyItem? in
            guard existing[word] == nil else { return nil }
            return VocabularyItem(term: word, translation: "待补充", example: "Practice using '\(word)' in your next call.")
        }
        if additions.isEmpty == false {
            snapshot.vocabulary.insert(contentsOf: additions, at: 0)
        }
    }

    private func mergeCarryOverVocabulary(_ terms: [String]) {
        var vocabularyByTerm = Dictionary(uniqueKeysWithValues: snapshot.vocabulary.map { ($0.term.lowercased(), $0) })

        for rawTerm in terms.prefix(4) {
            let trimmed = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.lowercased()
            guard normalized.isEmpty == false else { continue }

            if var existing = vocabularyByTerm[normalized] {
                existing.encounterCount += 1
                existing.updatedAt = .now
                if existing.mastery == .new {
                    existing.mastery = .practicing
                }
                vocabularyByTerm[normalized] = existing
            } else {
                vocabularyByTerm[normalized] = VocabularyItem(
                    term: trimmed,
                    translation: "待补充",
                    example: "Reuse '\(trimmed)' in your next call.",
                    mastery: .practicing
                )
            }
        }

        snapshot.vocabulary = vocabularyByTerm.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func upsertThreadState(from session: ConversationSession) {
        let state = ConversationThreadState(session: session)
        if let index = snapshot.threadStates.firstIndex(where: { $0.id == state.id }) {
            snapshot.threadStates[index] = state
        } else {
            snapshot.threadStates.insert(state, at: 0)
        }
        snapshot.threadStates.sort { $0.updatedAt > $1.updatedAt }
    }
}

extension FileMemoryStore {
    nonisolated func orderedPreviewVocabulary(from snapshot: MemorySnapshot) -> [VocabularyItem] {
        Array(snapshot.vocabulary.prefix(6))
    }
}

private extension Array where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
