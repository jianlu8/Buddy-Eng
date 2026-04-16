import Foundation

struct PromptComposer {
    func makePreface(
        learner: LearnerProfile,
        characterBundle: CharacterBundle,
        scene: CharacterScene,
        settings: CompanionSettings,
        memoryContext: String,
        mode: ConversationMode,
        scenario: ScenarioPreset,
        learningPlan: LearningFocusPlan,
        conversationLanguage: LanguageProfile,
        explanationLanguage: LanguageProfile,
        voiceBundle: VoiceBundle,
        continuation: ConversationSession? = nil
    ) -> ConversationPreface {
        let context = PromptContext(
            learner: learner,
            characterBundle: characterBundle,
            memoryContext: memoryContext,
            continuation: continuation,
            conversationLanguage: conversationLanguage,
            explanationLanguage: explanationLanguage,
            voiceBundle: voiceBundle
        )
        let explanationPolicy = explanationDirective(
            settings: settings,
            conversationLanguage: conversationLanguage,
            explanationLanguage: explanationLanguage
        )

        let responseStyle: String
        let modeDirective: String
        switch mode {
        case .chat:
            modeDirective = "Behave like a warm AI video-call companion who also quietly improves the learner's English. Protect flow first."
            responseStyle = "Keep replies short enough to feel interruptible, emotionally natural, and easy to continue. Ask only one follow-up at a time."
        case .tutor:
            modeDirective = "Behave like a proactive speaking tutor inside a video call. Push one micro-goal, ask for clearer retries, and track progress toward the current mission."
            responseStyle = "Keep replies brief but directional. Ask for one reason, one example, one comparison, or one restatement."
        }

        let systemPrompt = """
        You are \(characterBundle.characterProfile.displayName), an AI speaking companion inside a local-first iPhone video-call app.
        Persona: \(characterBundle.characterProfile.roleDescription)
        Character bundle: \(characterBundle.id)
        Speaking style: \(characterBundle.characterProfile.speakingStyle)
        Greeting style: \(characterBundle.characterProfile.greetingStyle)
        Memory tone: \(characterBundle.memoryTone)
        Voice style: \(voiceBundle.displayName) — \(voiceBundle.styleDescription)
        Scene: \(scene.title) — \(scene.ambienceDescription)
        Learner: \(context.learnerName). Level: \(learner.cefrEstimate.rawValue). Goal: \(context.learningGoal).
        Conversation language: \(conversationLanguage.conversationLanguage)
        Explanation language: \(explanationLanguage.explanationLanguage)
        Active scenario: \(scenario.title) — \(scenario.summary)
        Scenario category: \(scenario.category.title)
        Current mission: \(learningPlan.mission)
        Checkpoint: \(learningPlan.checkpoint)
        Success signal: \(learningPlan.successSignal)
        Pronunciation focus: \(learningPlan.pronunciationFocus.joined(separator: ", "))
        Carry-over vocabulary: \(learningPlan.carryOverVocabulary.joined(separator: ", "))
        Memory context:
        \(context.clampedMemoryContext)
        \(context.continuationDirective)
        \(explanationPolicy)
        \(modeDirective)
        \(responseStyle)
        Sound like a real call, not like a chatbot. Keep spoken replies easy to interrupt.
        Do not output stage directions, markdown, speaker labels, or quotation marks around speech.
        """

        let starterMessages: [String]
        switch mode {
        case .chat:
            starterMessages = [
                "Open like a real call and get the learner talking quickly.",
                "Stay warm, natural, and specific to the current scenario.",
                "If the learner is brief, ask for one more detail without sounding like a worksheet."
            ]
        case .tutor:
            starterMessages = [
                "Open by grounding the learner in the current mission immediately.",
                "Push one precise speaking target instead of giving many corrections at once.",
                "When the learner is vague, ask for a sharper retry with a reason or example."
            ]
        }

        return ConversationPreface(systemPrompt: systemPrompt, starterMessages: starterMessages)
    }

    func makeOpeningInstruction(
        learner: LearnerProfile,
        characterBundle: CharacterBundle,
        mode: ConversationMode,
        scenario: ScenarioPreset,
        learningPlan: LearningFocusPlan,
        conversationLanguage: LanguageProfile,
        explanationLanguage: LanguageProfile,
        continuation: ConversationSession? = nil
    ) -> String {
        let context = PromptContext(
            learner: learner,
            characterBundle: characterBundle,
            memoryContext: "",
            continuation: continuation,
            conversationLanguage: conversationLanguage,
            explanationLanguage: explanationLanguage,
            voiceBundle: VoiceCatalog.defaultBundle(
                for: characterBundle.characterProfile.id,
                languageID: conversationLanguage.id
            )
        )
        let name = learner.preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greetingTarget = name.isEmpty ? "the learner" : name
        let continuationPrefix = context.openingContinuationPrefix

        switch mode {
        case .chat:
            return """
            Start the call now as \(characterBundle.characterProfile.displayName). \(continuationPrefix)greet \(greetingTarget) naturally, make it feel like a live video call, and lead into the \(scenario.category.title.lowercased()) scenario "\(scenario.title)" in \(conversationLanguage.conversationLanguage). Keep it under two short spoken sentences and leave room for interruption. Use \(explanationLanguage.explanationLanguage) only if a quick clarification is needed.
            """
        case .tutor:
            return """
            Start the call now as \(characterBundle.characterProfile.displayName). \(continuationPrefix)greet \(greetingTarget), state the mission "\(learningPlan.mission)", and ask one short warm-up question for the \(scenario.category.title.lowercased()) scenario "\(scenario.title)" in \(conversationLanguage.conversationLanguage). Keep it under two short spoken sentences and leave room for interruption. Use \(explanationLanguage.explanationLanguage) only if a quick clarification is needed.
            """
        }
    }

    private func explanationDirective(
        settings: CompanionSettings,
        conversationLanguage: LanguageProfile,
        explanationLanguage: LanguageProfile
    ) -> String {
        if settings.allowChineseHints == false || explanationLanguage.id == conversationLanguage.id {
            return "Stay in \(conversationLanguage.conversationLanguage) unless the learner explicitly requests another language."
        }

        return """
        Keep the main spoken exchange in \(conversationLanguage.conversationLanguage).
        When the learner gets stuck or a correction needs clarification, use brief \(explanationLanguage.explanationLanguage) support, then return to \(conversationLanguage.conversationLanguage) immediately.
        """
    }
}

private struct PromptContext {
    let learnerName: String
    let learningGoal: String
    let clampedMemoryContext: String
    let continuationDirective: String
    let openingContinuationPrefix: String

    init(
        learner: LearnerProfile,
        characterBundle: CharacterBundle,
        memoryContext: String,
        continuation: ConversationSession?,
        conversationLanguage: LanguageProfile,
        explanationLanguage: LanguageProfile,
        voiceBundle: VoiceBundle
    ) {
        let trimmedName = learner.preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        learnerName = trimmedName.isEmpty ? "the learner" : trimmedName

        let trimmedGoal = learner.learningGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        learningGoal = trimmedGoal.isEmpty ? "build everyday speaking confidence" : trimmedGoal

        clampedMemoryContext = Self.clamp(memoryContext, max: 720)

        if let continuation {
            let previousScenario = continuation.scenarioID
                .map { ScenarioCatalog.preset(for: $0, mode: continuation.mode).title }
                ?? "your last topic"
            let summary = continuation.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastUserTurn = continuation.turns.last(where: { $0.role == .user })?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let feedbackCue = continuation.feedbackReport?.continuationCue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let carryForward = [summary, feedbackCue, lastUserTurn].first(where: { $0.isEmpty == false })
                ?? "Continue naturally from the most recent exchange if the learner keeps the same thread."

            continuationDirective = """
            Continuation: this call follows up on thread \(continuation.continuationThreadID) from a recent \(continuation.mode.title.lowercased()) session about \(previousScenario).
            Follow-up anchor: \(Self.clamp(carryForward, max: 220))
            """
            openingContinuationPrefix = "This is a follow-up to the recent call about \"\(previousScenario)\". Acknowledge the continuity naturally in one short clause, then "
        } else {
            continuationDirective = "Continuation: none. Start clean unless the learner asks to revisit an earlier topic."
            openingContinuationPrefix = ""
        }

        _ = characterBundle
        _ = conversationLanguage
        _ = explanationLanguage
        _ = voiceBundle
    }

    private static func clamp(_ value: String, max: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
