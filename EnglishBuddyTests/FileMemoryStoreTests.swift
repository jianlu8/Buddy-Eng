import XCTest
@testable import EnglishBuddyCore

final class FileMemoryStoreTests: XCTestCase {
    func testPersistsAndReloadsSnapshot() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filesystem = AppFilesystem(baseURL: baseURL)
        let store = FileMemoryStore(filesystem: filesystem)

        try await store.load()
        try await store.updateLearnerProfile {
            $0.preferredName = "Hammond"
            $0.learningGoal = "Speak smoothly in meetings"
        }
        try await store.updateCompanionSettings {
            $0.visualStyle = .cinematic
            $0.conversationLanguageID = LanguageCatalog.japanese.id
            $0.explanationLanguageID = LanguageCatalog.english.id
            $0.selectedVoiceBundleID = VoiceCatalog.defaultBundle(for: CharacterCatalog.flagship.id, languageID: LanguageCatalog.japanese.id).id
        }
        try await store.upsertSession(
            ConversationSession(
                mode: .chat,
                summary: "Talked about work",
                keyMoments: ["small talk"],
                turns: [ConversationTurn(role: .user, text: "I want better English for meetings.")],
                voiceBundleID: VoiceCatalog.defaultBundle(for: CharacterCatalog.flagship.id, languageID: LanguageCatalog.japanese.id).id,
                languageProfileID: LanguageCatalog.japanese.id
            )
        )

        let reloaded = FileMemoryStore(filesystem: filesystem)
        try await reloaded.load()
        let snapshot = await reloaded.fetchSnapshot()

        XCTAssertEqual(snapshot.learnerProfile.preferredName, "Hammond")
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions.first?.summary, "Talked about work")
        XCTAssertEqual(snapshot.companionSettings.visualStyle, .cinematic)
        XCTAssertEqual(snapshot.companionSettings.conversationLanguageID, LanguageCatalog.japanese.id)
        XCTAssertEqual(snapshot.companionSettings.explanationLanguageID, LanguageCatalog.english.id)
        XCTAssertEqual(snapshot.sessions.first?.languageProfileID, LanguageCatalog.japanese.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.userDataSnapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.modelStateSnapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.assetStateSnapshotURL.path))
    }

    func testSaveSessionFeedbackPromotesCarryOverVocabularyIntoVocabularyQueue() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filesystem = AppFilesystem(baseURL: baseURL)
        let store = FileMemoryStore(filesystem: filesystem)

        try await store.load()
        let session = ConversationSession(mode: .tutor)
        try await store.upsertSession(session)

        try await store.saveSessionFeedback(
            FeedbackReport(carryOverVocabulary: ["schedule", "clarify"]),
            sessionID: session.id
        )

        let snapshot = await store.fetchSnapshot()
        XCTAssertTrue(snapshot.learnerProfile.favoriteTopics.isEmpty)
        XCTAssertEqual(snapshot.vocabulary.prefix(2).map(\.term), ["clarify", "schedule"])
        XCTAssertEqual(snapshot.vocabulary.prefix(2).map(\.mastery), [.practicing, .practicing])
    }

    func testUpdateCompanionSettingsNormalizesPortraitCompatibilityFlag() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filesystem = AppFilesystem(baseURL: baseURL)
        let store = FileMemoryStore(filesystem: filesystem)

        try await store.load()
        try await store.updateCompanionSettings {
            $0.portraitModeEnabled = false
        }

        let snapshot = await store.fetchSnapshot()
        XCTAssertEqual(snapshot.companionSettings.portraitModeEnabled, CharacterCatalog.primaryPortraitAvailable)
    }

    func testThreadStateTracksLatestMissionAndContinuationCue() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filesystem = AppFilesystem(baseURL: baseURL)
        let store = FileMemoryStore(filesystem: filesystem)

        try await store.load()
        let threadID = "thread-123"
        let session = ConversationSession(
            mode: .tutor,
            summary: "Worked on clearer meeting answers.",
            scenarioID: "clarify-an-opinion",
            continuationThreadID: threadID,
            learningPlanSnapshot: LearningFocusPlan(
                title: "Micro-goal for this call",
                mission: "Give one opinion with a reason.",
                checkpoint: "Ask for one clearer follow-up.",
                successSignal: "One reason and one example.",
                pronunciationFocus: ["world"],
                carryOverVocabulary: ["clarify"]
            )
        )
        try await store.upsertSession(session)
        try await store.saveSessionFeedback(
            FeedbackReport(
                pronunciationHighlights: ["Repeat 'world' once slowly, then in a full sentence."],
                carryOverVocabulary: ["clarify", "example"],
                nextMission: "Next time, reuse clarify in a longer meeting answer.",
                continuationCue: "Resume from the meeting example and extend it with one detail."
            ),
            sessionID: session.id
        )

        let snapshot = await store.fetchSnapshot()
        XCTAssertEqual(snapshot.threadStates.count, 1)
        XCTAssertEqual(snapshot.threadStates.first?.id, threadID)
        XCTAssertEqual(snapshot.threadStates.first?.latestSessionID, session.id)
        XCTAssertEqual(snapshot.threadStates.first?.currentMission, "Give one opinion with a reason.")
        XCTAssertEqual(snapshot.threadStates.first?.nextMission, "Next time, reuse clarify in a longer meeting answer.")
        XCTAssertEqual(snapshot.threadStates.first?.continuationCue, "Resume from the meeting example and extend it with one detail.")
        XCTAssertEqual(snapshot.threadStates.first?.carryOverVocabulary, ["clarify", "example"])
        XCTAssertEqual(snapshot.threadStates.first?.pronunciationTargets, ["world"])
    }

    func testLegacySnapshotMigratesIntoSplitStores() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filesystem = AppFilesystem(baseURL: baseURL)

        try filesystem.prepareDirectories()
        let legacySnapshot = MemorySnapshot(
            learnerProfile: LearnerProfile(
                preferredName: "Legacy",
                learningGoal: "Keep older installs working.",
                preferredMode: .chat,
                cefrEstimate: .b1,
                favoriteTopics: ["retrofit"],
                commonMistakes: [],
                firstSessionAt: nil,
                updatedAt: .now
            ),
            companionSettings: .default,
            sessions: [ConversationSession(mode: .chat, summary: "Legacy session")],
            threadStates: [],
            vocabulary: [VocabularyItem(term: "legacy", translation: "旧版", example: "Legacy import test.")],
            modelInstallationRecords: ModelCatalog.current.defaultRecords(),
            modelSelectionState: ModelCatalog.current.defaultSelectionState
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacySnapshot).write(to: filesystem.snapshotURL, options: .atomic)

        let store = FileMemoryStore(filesystem: filesystem)
        try await store.load()

        let snapshot = await store.fetchSnapshot()
        XCTAssertEqual(snapshot.learnerProfile.preferredName, "Legacy")
        XCTAssertEqual(snapshot.sessions.first?.summary, "Legacy session")
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.userDataSnapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.modelStateSnapshotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: filesystem.migrationReceiptURL.path))
    }
}
