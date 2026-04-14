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
        try await store.upsertSession(
            ConversationSession(
                mode: .chat,
                summary: "Talked about work",
                keyMoments: ["small talk"],
                turns: [ConversationTurn(role: .user, text: "I want better English for meetings.")]
            )
        )

        let reloaded = FileMemoryStore(filesystem: filesystem)
        try await reloaded.load()
        let snapshot = await reloaded.fetchSnapshot()

        XCTAssertEqual(snapshot.learnerProfile.preferredName, "Hammond")
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions.first?.summary, "Talked about work")
    }
}
