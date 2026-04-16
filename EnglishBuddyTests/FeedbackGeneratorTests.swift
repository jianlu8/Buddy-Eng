import XCTest
@testable import EnglishBuddyCore

final class FeedbackGeneratorTests: XCTestCase {
    func testGeneratesGrammarAndVocabularyHints() {
        let generator = FeedbackGenerator()
        let session = ConversationSession(
            mode: .tutor,
            turns: [
                ConversationTurn(role: .user, text: "Yesterday I go to work and he go with me. It was very good."),
                ConversationTurn(role: .assistant, text: "Tell me more.")
            ]
        )

        let report = generator.generateFeedback(for: session, learner: .default, mode: .tutor)

        XCTAssertFalse(report.grammarIssues.isEmpty)
        XCTAssertFalse(report.vocabularySuggestions.isEmpty)
        XCTAssertFalse(report.nextTopicSuggestions.isEmpty)
    }

    func testSummarizesSessionWithHighlights() {
        let generator = FeedbackGenerator()
        let session = ConversationSession(
            mode: .chat,
            turns: [
                ConversationTurn(role: .user, text: "I like travel because it gives me freedom."),
                ConversationTurn(role: .assistant, text: "Where would you like to go next?"),
                ConversationTurn(role: .user, text: "I want to visit Japan and try local food.")
            ]
        )

        let summary = generator.summarizeSession(session)
        XCTAssertTrue(summary.summary.contains("travel") || summary.summary.contains("daily life"))
        XCTAssertEqual(summary.keyMoments.count, 3)
    }

    func testFeedbackCarriesVoiceBundleAndReferenceAccentFromSession() {
        let generator = FeedbackGenerator()
        let session = ConversationSession(
            mode: .tutor,
            turns: [
                ConversationTurn(role: .user, text: "I want to improve my pronunciation in British English."),
                ConversationTurn(role: .assistant, text: "Let's slow down and make each sentence clearer.")
            ],
            voiceBundleID: "lyra-voice",
            voiceAccent: .british
        )

        let report = generator.generateFeedback(for: session, learner: .default, mode: .tutor)

        XCTAssertEqual(report.voiceBundleID, "lyra-voice")
        XCTAssertEqual(report.voiceDisplayName, "British Female")
        XCTAssertEqual(report.referenceAccent, EnglishAccent.british)
        XCTAssertEqual(report.referenceAccentDisplayName, EnglishAccent.british.displayName)
    }
}
