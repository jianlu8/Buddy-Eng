import Foundation

struct PromptComposer {
    func makePreface(
        learner: LearnerProfile,
        character: CharacterProfile,
        scene: CharacterScene,
        settings: CompanionSettings,
        memoryContext: String,
        mode: ConversationMode,
        scenario: ScenarioPreset,
        learningPlan: LearningFocusPlan
    ) -> ConversationPreface {
        let chinesePolicy = settings.allowChineseHints
            ? "Use English for practice. Use concise Simplified Chinese only when a correction needs clarification."
            : "Stay in English unless the learner explicitly asks for Chinese."

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

        let goal = learner.learningGoal.isEmpty ? "build everyday speaking confidence" : learner.learningGoal
        let name = learner.preferredName.isEmpty ? "the learner" : learner.preferredName

        let systemPrompt = """
        You are \(character.displayName), an AI speaking companion inside an offline iPhone app.
        Persona: \(character.roleDescription)
        Speaking style: \(character.speakingStyle)
        Greeting style: \(character.greetingStyle)
        Scene: \(scene.title) — \(scene.ambienceDescription)
        Learner: \(name). Level: \(learner.cefrEstimate.rawValue). Goal: \(goal).
        Active scenario: \(scenario.title) — \(scenario.summary)
        Current mission: \(learningPlan.mission)
        Checkpoint: \(learningPlan.checkpoint)
        Success signal: \(learningPlan.successSignal)
        Pronunciation focus: \(learningPlan.pronunciationFocus.joined(separator: ", "))
        Carry-over vocabulary: \(learningPlan.carryOverVocabulary.joined(separator: ", "))
        Memory context:
        \(memoryContext)
        \(chinesePolicy)
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
        character: CharacterProfile,
        mode: ConversationMode,
        scenario: ScenarioPreset,
        learningPlan: LearningFocusPlan
    ) -> String {
        let name = learner.preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greetingTarget = name.isEmpty ? "the learner" : name

        switch mode {
        case .chat:
            return """
            Start the call now as \(character.displayName). Greet \(greetingTarget) naturally, make it feel like a live video call, and lead into the scenario "\(scenario.title)". Keep it under two short spoken sentences and leave room for interruption.
            """
        case .tutor:
            return """
            Start the call now as \(character.displayName). Greet \(greetingTarget), state the mission "\(learningPlan.mission)", and ask one short warm-up question for the scenario "\(scenario.title)". Keep it under two short spoken sentences and leave room for interruption.
            """
        }
    }
}
