import Foundation

struct FeedbackGenerator {
    func generateFeedback(
        for session: ConversationSession,
        learner: LearnerProfile,
        mode: ConversationMode
    ) -> FeedbackReport {
        let userTurns = session.turns.filter { $0.role == .user }
        let fullText = userTurns.map(\.text).joined(separator: " ").lowercased()
        let grammar = detectGrammarIssues(in: userTurns).prefix(3)
        let vocabulary = detectVocabularySuggestions(in: userTurns).prefix(3)
        let pronunciation = detectPronunciationTips(in: fullText).prefix(3)
        let frequentExpressions = extractFrequentExpressions(from: userTurns)
        let nextTopics = suggestNextTopics(from: fullText, goal: learner.learningGoal, mode: mode)
        let carryOverVocabulary = extractCarryOverVocabulary(from: userTurns)
        let pronunciationHighlights = makePronunciationHighlights(
            session: session,
            pronunciation: Array(pronunciation),
            fullText: fullText
        )
        let nextMission = makeNextMission(
            session: session,
            learner: learner,
            mode: mode,
            carryOverVocabulary: carryOverVocabulary
        )
        let goalCompletionSummary = makeGoalCompletionSummary(
            session: session,
            learner: learner,
            mode: mode,
            userTurns: userTurns
        )

        return FeedbackReport(
            grammarIssues: Array(grammar),
            vocabularySuggestions: Array(vocabulary),
            pronunciationTips: Array(pronunciation),
            frequentExpressions: frequentExpressions,
            nextTopicSuggestions: nextTopics,
            pronunciationHighlights: pronunciationHighlights,
            carryOverVocabulary: carryOverVocabulary,
            nextMission: nextMission,
            goalCompletionSummary: goalCompletionSummary
        )
    }

    func summarizeSession(_ session: ConversationSession) -> (summary: String, keyMoments: [String]) {
        let userTurns = session.turns.filter { $0.role == .user }
        let opener = userTurns.first?.text ?? "Learner started a short warm-up."
        let latest = userTurns.last?.text ?? opener
        let character = CharacterCatalog.profile(for: session.characterID)
        let scenarioTitle = session.scenarioID.flatMap { ScenarioCatalog.preset(for: $0, mode: session.mode).title } ?? "Open Conversation"
        let summary: String
        let moments: [String]

        switch session.mode {
        case .chat:
            summary = "\(character.displayName) kept a natural video-call flow around \(dominantTopic(in: userTurns)) and moved from '\(shorten(opener))' toward '\(shorten(latest))'."
            moments = [
                "Scenario: \(scenarioTitle)",
                "Best reusable phrase: \(extractFrequentExpressions(from: userTurns).first ?? "kept the conversation moving")",
                "Next flow target: \(detectVocabularySuggestions(in: userTurns).first?.suggestion ?? "add one more detail to each answer")"
            ]
        case .tutor:
            let fullTutorText = userTurns.map(\.text).joined(separator: " ").lowercased()
            summary = "\(character.displayName) coached one focused speaking mission around \(dominantTopic(in: userTurns)) and pushed the answer from '\(shorten(opener))' toward '\(shorten(latest))'."
            moments = [
                "Scenario: \(scenarioTitle)",
                "Main correction target: \(detectGrammarIssues(in: userTurns).first?.suggestion ?? "make answers more structured")",
                "Next drill: \(suggestNextTopics(from: fullTutorText, goal: "", mode: .tutor).first ?? "repeat the same topic with one clearer reason")"
            ]
        }
        return (summary, moments)
    }

    private func detectGrammarIssues(in turns: [ConversationTurn]) -> [CorrectionEvent] {
        let joined = turns.map(\.text).joined(separator: " ")
        var issues: [CorrectionEvent] = []

        let patterns: [(String, String, String)] = [
            ("he go", "he goes", "第三人称单数要加 s。"),
            ("she go", "she goes", "第三人称单数要加 s。"),
            ("i very like", "I really like", "英语里通常用 really 来修饰 like。"),
            ("yesterday i go", "yesterday I went", "过去时间要用过去式。"),
            ("people is", "people are", "people 是复数。")
        ]

        for (source, suggestion, explanation) in patterns where joined.lowercased().contains(source) {
            issues.append(CorrectionEvent(category: .grammar, source: source, suggestion: suggestion, explanation: explanation))
        }

        if issues.isEmpty, let longTurn = turns.first(where: { $0.text.contains("because") == false && $0.text.split(whereSeparator: \.isWhitespace).count > 10 }) {
            issues.append(
                CorrectionEvent(
                    category: .grammar,
                    source: shorten(longTurn.text),
                    suggestion: "Try connecting longer answers with because / so / but.",
                    explanation: "长句之间加连接词，会更自然也更清楚。"
                )
            )
        }

        return issues
    }

    private func detectVocabularySuggestions(in turns: [ConversationTurn]) -> [CorrectionEvent] {
        let text = turns.map(\.text).joined(separator: " ").lowercased()
        var suggestions: [CorrectionEvent] = []

        if text.contains("very good") {
            suggestions.append(CorrectionEvent(category: .vocabulary, source: "very good", suggestion: "excellent / solid / impressive", explanation: "避免重复 very good，可以换更具体的词。"))
        }
        if text.contains("i think") {
            suggestions.append(CorrectionEvent(category: .vocabulary, source: "I think", suggestion: "From my perspective / I'd say", explanation: "减少重复起手式，让表达更高级。"))
        }
        if text.contains("thing") {
            suggestions.append(CorrectionEvent(category: .vocabulary, source: "thing", suggestion: "detail / idea / habit / situation", explanation: "把笼统名词换成具体词，会更地道。"))
        }
        if suggestions.isEmpty, let term = turns.flatMap({ $0.text.split(whereSeparator: \.isWhitespace) }).map(String.init).first(where: { $0.count > 5 }) {
            suggestions.append(CorrectionEvent(category: .vocabulary, source: term, suggestion: "Reuse '\(term)' in a new sentence about your daily life.", explanation: "把会说的词放进新语境，记忆会更稳。"))
        }

        return suggestions
    }

    private func detectPronunciationTips(in fullText: String) -> [CorrectionEvent] {
        var tips: [CorrectionEvent] = []
        if fullText.contains("th") {
            tips.append(CorrectionEvent(category: .pronunciation, source: "th sounds", suggestion: "Practice tongue-between-teeth for think / this.", explanation: "注意咬舌音，别把 th 都说成 s 或 d。"))
        }
        if fullText.contains("world") || fullText.contains("work") {
            tips.append(CorrectionEvent(category: .pronunciation, source: "r/l contrast", suggestion: "Slow down on world / work and hold the r longer.", explanation: "这组词常见问题是 r 和 l 混淆。"))
        }
        if tips.isEmpty {
            tips.append(CorrectionEvent(category: .pronunciation, source: "sentence rhythm", suggestion: "Stress the content words and shorten small function words.", explanation: "v1 用词级启发式反馈，你可以先练句子节奏。"))
        }
        return tips
    }

    private func extractFrequentExpressions(from turns: [ConversationTurn]) -> [String] {
        let stopWords = Set(["the", "and", "but", "for", "that", "with", "have", "this", "from", "your", "about"])
        let tokens = turns
            .flatMap { $0.text.lowercased().components(separatedBy: CharacterSet.letters.inverted) }
            .filter { $0.count >= 4 && stopWords.contains($0) == false }
        let counts = Dictionary(tokens.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }
        .prefix(3)
        .map { $0.key }
    }

    private func extractCarryOverVocabulary(from turns: [ConversationTurn]) -> [String] {
        let candidates = turns
            .flatMap { $0.text.split(whereSeparator: \.isWhitespace) }
            .map { String($0).trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { $0.count >= 5 }
        return Array(candidates.orderedUnique().prefix(4))
    }

    private func makePronunciationHighlights(
        session: ConversationSession,
        pronunciation: [CorrectionEvent],
        fullText: String
    ) -> [String] {
        if let learningPlan = session.learningPlanSnapshot, learningPlan.pronunciationFocus.isEmpty == false {
            return learningPlan.pronunciationFocus.map { word in
                "Repeat '\(word)' once slowly, then once inside a full sentence."
            }
        }
        if fullText.contains("th") {
            return ["Repeat think / this / those with a longer th release."]
        }
        return pronunciation.prefix(2).map { "\($0.source): \($0.suggestion)" }
    }

    private func suggestNextTopics(from fullText: String, goal: String, mode: ConversationMode) -> [String] {
        var topics: [String] = []
        if fullText.contains("travel") || goal.lowercased().contains("travel") {
            topics.append("机场和酒店场景英语")
        }
        if fullText.contains("work") || goal.lowercased().contains("work") {
            topics.append("英文会议里的观点表达")
        }
        if fullText.contains("food") {
            topics.append("点餐和表达口味偏好")
        }
        topics.append(mode == .tutor ? "围绕同一话题做 90 秒连续表达" : "延续今天的话题，再多讲一个个人故事")
        return Array(topics.orderedUnique().prefix(3))
    }

    private func makeNextMission(
        session: ConversationSession,
        learner: LearnerProfile,
        mode: ConversationMode,
        carryOverVocabulary: [String]
    ) -> String {
        let scenario = ScenarioCatalog.preset(for: session.scenarioID, mode: mode)
        let vocabularyText = carryOverVocabulary.prefix(2).joined(separator: ", ")
        let goal = learner.learningGoal.trimmingCharacters(in: .whitespacesAndNewlines)

        if mode == .tutor {
            let vocabularyClause = vocabularyText.isEmpty ? "" : " while reusing \(vocabularyText)"
            return "Next time, stay with \(scenario.title.lowercased()) and answer with one reason plus one example\(vocabularyClause)."
        }
        if goal.isEmpty == false {
            return "Next call, keep the same character and connect the conversation back to your goal: \(goal)."
        }
        return "Next call, keep the same character and turn one short answer into a longer personal story."
    }

    private func makeGoalCompletionSummary(
        session: ConversationSession,
        learner: LearnerProfile,
        mode: ConversationMode,
        userTurns: [ConversationTurn]
    ) -> String {
        let averageWordCount = userTurns.isEmpty ? 0 : userTurns.map { $0.text.split(whereSeparator: \.isWhitespace).count }.reduce(0, +) / userTurns.count
        let mission = session.learningPlanSnapshot?.mission ?? learner.learningGoal

        if mode == .tutor {
            return averageWordCount >= 10
                ? "You stayed on the mission and gave fuller answers than a one-line response."
                : "The mission is set. Next round, push the answer one step further with a reason and example."
        }
        return mission.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "This call kept your practice connected to '\(mission)'."
            : "This call built continuity and gave you material to reuse next time."
    }

    private func dominantTopic(in turns: [ConversationTurn]) -> String {
        let text = turns.map(\.text).joined(separator: " ").lowercased()
        let mapping = [
            ("travel", "travel"),
            ("work", "work"),
            ("study", "study"),
            ("movie", "movies"),
            ("food", "food"),
            ("family", "family")
        ]
        return mapping.first(where: { text.contains($0.0) })?.1 ?? "daily life"
    }

    private func shorten(_ text: String, maxLength: Int = 44) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private extension Array where Element == String {
    func orderedUnique() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
