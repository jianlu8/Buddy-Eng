import Foundation

actor FileMemoryStore: MemoryStore {
    private let filesystem: AppFilesystem
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var snapshot: MemorySnapshot

    init(filesystem: AppFilesystem) {
        self.filesystem = filesystem
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
        try filesystem.prepareDirectories()
        guard FileManager.default.fileExists(atPath: filesystem.snapshotURL.path) else {
            try persist()
            return
        }

        let data = try Data(contentsOf: filesystem.snapshotURL)
        snapshot = try decoder.decode(MemorySnapshot.self, from: data)
    }

    func fetchSnapshot() -> MemorySnapshot {
        snapshot
    }

    func fetchPersonaSummary() -> String {
        let profile = snapshot.learnerProfile
        let settings = snapshot.companionSettings
        let character = CharacterCatalog.profile(for: settings.selectedCharacterID)
        let scene = CharacterCatalog.scene(for: settings.selectedSceneID, characterID: character.id)
        let topics = profile.favoriteTopics.prefix(3).joined(separator: ", ")
        let mistakes = profile.commonMistakes.prefix(3).joined(separator: ", ")
        return """
        Learner: \(profile.preferredName.isEmpty ? "Anonymous" : profile.preferredName)
        Goal: \(profile.learningGoal.isEmpty ? "Speak more confidently in everyday English." : profile.learningGoal)
        CEFR: \(profile.cefrEstimate.rawValue)
        Character: \(character.displayName), scene=\(scene.title), chineseHints=\(settings.allowChineseHints ? "on" : "off"), speechRate=\(settings.speechRate)
        Topics: \(topics.isEmpty ? "daily life, travel, work" : topics)
        Common mistakes: \(mistakes.isEmpty ? "none collected yet" : mistakes)
        """
    }

    func fetchLearningContext() -> String {
        let recentSessions = snapshot.sessions.sorted { $0.startedAt > $1.startedAt }.prefix(3)
        guard recentSessions.isEmpty == false else { return "No previous sessions yet." }

        return recentSessions.map { session in
            let highlights = session.keyMoments.prefix(2).joined(separator: "; ")
            let character = CharacterCatalog.profile(for: session.characterID)
            let scenario = session.scenarioID.flatMap { ScenarioCatalog.preset(for: $0, mode: session.mode).title } ?? "Open Conversation"
            return "[\(session.mode.title)] \(character.displayName) • \(scenario) • \(session.summary) Highlights: \(highlights)"
        }.joined(separator: "\n")
    }

    func saveTurn(_ turn: ConversationTurn, sessionID: UUID) async throws {
        guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        snapshot.sessions[index].turns.append(turn)
        try absorbVocabulary(from: turn)
        try persist()
    }

    func saveSessionFeedback(_ feedback: FeedbackReport, sessionID: UUID) async throws {
        guard let index = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        snapshot.sessions[index].feedbackReport = feedback
        let newMistakes = feedback.grammarIssues.map(\.source) + feedback.pronunciationTips.map(\.source)
        snapshot.learnerProfile.commonMistakes = Array((newMistakes + snapshot.learnerProfile.commonMistakes).orderedUnique().prefix(8))
        if feedback.carryOverVocabulary.isEmpty == false {
            let newFavorites = feedback.carryOverVocabulary.prefix(3)
            snapshot.learnerProfile.favoriteTopics = Array((newFavorites + snapshot.learnerProfile.favoriteTopics).orderedUnique().prefix(8))
        }
        snapshot.learnerProfile.updatedAt = .now
        try persist()
    }

    func upsertSession(_ session: ConversationSession) async throws {
        if let index = snapshot.sessions.firstIndex(where: { $0.id == session.id }) {
            snapshot.sessions[index] = session
        } else {
            snapshot.sessions.insert(session, at: 0)
        }
        snapshot.learnerProfile.firstSessionAt = snapshot.learnerProfile.firstSessionAt ?? session.startedAt
        snapshot.learnerProfile.cefrEstimate = estimateCEFR(from: snapshot.sessions)
        snapshot.learnerProfile.updatedAt = .now
        try persist()
    }

    func updateLearnerProfile(_ mutate: @Sendable (inout LearnerProfile) -> Void) async throws {
        mutate(&snapshot.learnerProfile)
        snapshot.learnerProfile.updatedAt = .now
        try persist()
    }

    func updateCompanionSettings(_ mutate: @Sendable (inout CompanionSettings) -> Void) async throws {
        mutate(&snapshot.companionSettings)
        snapshot.companionSettings.selectedCharacterID = CharacterCatalog.profile(for: snapshot.companionSettings.selectedCharacterID).id
        snapshot.companionSettings.selectedSceneID = CharacterCatalog.scene(
            for: snapshot.companionSettings.selectedSceneID,
            characterID: snapshot.companionSettings.selectedCharacterID
        ).id
        try persist()
    }

    func upsertVocabulary(_ vocabulary: [VocabularyItem]) async throws {
        var dictionary = Dictionary(uniqueKeysWithValues: snapshot.vocabulary.map { ($0.term.lowercased(), $0) })
        for item in vocabulary {
            dictionary[item.term.lowercased()] = item
        }
        snapshot.vocabulary = dictionary.values.sorted { $0.updatedAt > $1.updatedAt }
        try persist()
    }

    func deleteAllMemory() async throws {
        snapshot = .default
        try persist()
    }

    func updateModelCatalogState(records: [ModelInstallationRecord], selectionState: ModelSelectionState) async throws {
        snapshot.modelInstallationRecords = ModelCatalog.current.mergedRecords(with: records)
        snapshot.modelSelectionState = selectionState
        try persist()
    }

    func updateModelSelectionState(_ selectionState: ModelSelectionState) async throws {
        snapshot.modelSelectionState = selectionState
        try persist()
    }

    func updateModelInstallationRecord(_ record: ModelInstallationRecord) async throws {
        var recordsByID = Dictionary(uniqueKeysWithValues: snapshot.modelInstallationRecords.map { ($0.modelID, $0) })
        recordsByID[record.modelID] = record
        snapshot.modelInstallationRecords = ModelCatalog.current.mergedRecords(with: Array(recordsByID.values))
        try persist()
    }

    private func persist() throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: filesystem.snapshotURL, options: .atomic)
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
