import Foundation

@MainActor
final class LocalPostCallReviewRuntime: PostCallReviewRuntimeProtocol {
    func refineFeedback(
        _ feedback: FeedbackReport,
        for session: ConversationSession,
        learner: LearnerProfile
    ) async -> FeedbackReport {
        guard session.mode == .tutor else { return feedback }

        let userTurns = session.turns.filter { $0.role == .user }
        let learningPlan = session.learningPlanSnapshot
        let scenario = ScenarioCatalog.preset(for: session.scenarioID, mode: session.mode)
        let carryOverVocabulary = buildCarryOverVocabulary(
            feedback: feedback,
            learningPlan: learningPlan,
            userTurns: userTurns
        )
        let pronunciationHighlights = buildPronunciationHighlights(
            feedback: feedback,
            learningPlan: learningPlan,
            userTurns: userTurns
        )

        var refined = feedback
        refined.carryOverVocabulary = carryOverVocabulary
        refined.pronunciationHighlights = pronunciationHighlights
        refined.goalCompletionSummary = buildGoalCompletionSummary(
            session: session,
            learner: learner,
            userTurns: userTurns
        )
        refined.nextMission = buildNextMission(
            scenario: scenario,
            learningPlan: learningPlan,
            carryOverVocabulary: carryOverVocabulary,
            fallback: feedback.nextMission
        )
        refined.continuationCue = buildContinuationCue(
            scenario: scenario,
            learningPlan: learningPlan,
            userTurns: userTurns,
            carryOverVocabulary: carryOverVocabulary,
            fallback: feedback.continuationCue
        )
        refined.nextThemeSuggestion = buildNextThemeSuggestion(scenario: scenario)
        return refined
    }

    private func buildCarryOverVocabulary(
        feedback: FeedbackReport,
        learningPlan: LearningFocusPlan?,
        userTurns: [ConversationTurn]
    ) -> [String] {
        let transcriptCandidates = userTurns
            .flatMap { extractCandidateWords(from: $0.text) }
            .filter { $0.count >= 5 }

        return Array(
            (feedback.carryOverVocabulary + (learningPlan?.carryOverVocabulary ?? []) + transcriptCandidates)
                .orderedUnique()
                .prefix(4)
        )
    }

    private func buildPronunciationHighlights(
        feedback: FeedbackReport,
        learningPlan: LearningFocusPlan?,
        userTurns: [ConversationTurn]
    ) -> [String] {
        if let focus = learningPlan?.pronunciationFocus, focus.isEmpty == false {
            return focus.map { word in
                "Repeat '\(word)' once slowly, then once inside a fuller answer."
            }
        }

        if feedback.pronunciationHighlights.isEmpty == false {
            return Array(feedback.pronunciationHighlights.prefix(3))
        }

        let feedbackTargets = feedback.pronunciationTips
            .flatMap { extractCandidateWords(from: "\($0.source) \($0.suggestion)") }
        let transcriptTargets = userTurns.flatMap { extractCandidateWords(from: $0.text) }
        let targets = Array((feedbackTargets + transcriptTargets).orderedUnique().prefix(2))

        if targets.isEmpty {
            return ["Repeat one key sentence slowly, then say it again at natural rhythm."]
        }

        return targets.map { word in
            "Repeat '\(word)' once slowly, then once in a complete sentence."
        }
    }

    private func buildGoalCompletionSummary(
        session: ConversationSession,
        learner: LearnerProfile,
        userTurns: [ConversationTurn]
    ) -> String {
        let mission = session.learningPlanSnapshot?.mission.nonEmpty
            ?? learner.learningGoal.nonEmpty
            ?? "Keep one clear speaking mission for the next tutor call."
        let checkpoint = session.learningPlanSnapshot?.checkpoint.nonEmpty
        let turnCount = userTurns.count
        let averageWordCount = userTurns.isEmpty ? 0 : userTurns.map { wordCount(for: $0) }.reduce(0, +) / userTurns.count

        if turnCount >= 2 || averageWordCount >= 9 {
            if let checkpoint {
                return "Mission check: \(mission) You kept \(turnCount) learner replies moving and landed the checkpoint: \(checkpoint)."
            }
            return "Mission check: \(mission) You kept \(turnCount) learner replies moving at about \(averageWordCount) words per turn."
        }

        if let checkpoint {
            return "Mission check: \(mission) You started the drill, but the next call still needs a clearer checkpoint hit: \(checkpoint)."
        }

        return "Mission check: \(mission) You started the drill, and the next call should add one clearer reason plus one follow-up."
    }

    private func buildNextMission(
        scenario: ScenarioPreset,
        learningPlan: LearningFocusPlan?,
        carryOverVocabulary: [String],
        fallback: String
    ) -> String {
        let checkpoint = learningPlan?.checkpoint.nonEmpty?.sentenceFragment
        let carryOver = carryOverVocabulary.prefix(2).joined(separator: ", ")
        let carryClause = carryOver.isEmpty ? "" : " while reusing \(carryOver)"

        if let checkpoint {
            return "Next tutor call: stay with \(scenario.title.lowercased()), \(checkpoint)\(carryClause)."
        }

        if fallback.nonEmpty != nil {
            return fallback
        }

        return "Next tutor call: stay with \(scenario.title.lowercased()) and add one clearer reason plus one example\(carryClause)."
    }

    private func buildContinuationCue(
        scenario: ScenarioPreset,
        learningPlan: LearningFocusPlan?,
        userTurns: [ConversationTurn],
        carryOverVocabulary: [String],
        fallback: String
    ) -> String {
        let checkpoint = learningPlan?.checkpoint.nonEmpty?.sentenceFragment
        let carryOver = carryOverVocabulary.prefix(2).joined(separator: ", ")

        if let anchor = userTurns.last?.text.nonEmpty {
            let anchorText = shorten(anchor, maxLength: 58)
            var cue = "Resume \(scenario.title) from \"\(anchorText)\""
            if let checkpoint {
                cue += " and \(checkpoint)"
            }
            cue += "."
            if carryOver.isEmpty == false {
                cue += " Reuse \(carryOver)."
            }
            return cue
        }

        if fallback.nonEmpty != nil {
            return fallback
        }

        if let checkpoint {
            return "Resume \(scenario.title) and \(checkpoint)."
        }

        return "Resume the same tutor thread and extend the previous answer with one clearer detail."
    }

    private func buildNextThemeSuggestion(scenario: ScenarioPreset) -> String {
        switch scenario.category {
        case .freeTalk:
            return "Keep the same character and shift the free talk toward one adjacent daily-life angle."
        case .lectureStyleExplanation:
            return "Ask for one new explanation, then paraphrase it back in your own words."
        case .roleplayPractice:
            return "Replay the same roleplay with one added constraint or follow-up question."
        case .gameThemeChallenge:
            return "Keep the same playful challenge and answer faster with fewer pauses."
        case .pronunciationDrill:
            return "Keep the drill, then move the target word into a longer sentence."
        case .vocabularyCarryOver:
            return "Reuse the saved vocabulary in a fresh example instead of repeating the same answer."
        }
    }

    private func extractCandidateWords(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "about", "again", "answer", "because", "call", "clearer", "detail", "example",
            "fully", "inside", "learner", "mission", "practice", "question", "repeat",
            "reply", "sentence", "slowly", "still", "their", "there", "these", "thing",
            "topic", "tutor", "using", "with", "would", "your"
        ]

        return text
            .components(separatedBy: CharacterSet.letters.inverted)
            .map { $0.lowercased() }
            .filter { token in
                token.count >= 4 && stopWords.contains(token) == false
            }
    }

    private func wordCount(for turn: ConversationTurn) -> Int {
        turn.text.split(whereSeparator: \.isWhitespace).count
    }

    private func shorten(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private extension Array where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var sentenceFragment: String {
        trimmingCharacters(in: CharacterSet(charactersIn: ".!? ").union(.whitespacesAndNewlines))
            .lowercased()
    }
}
