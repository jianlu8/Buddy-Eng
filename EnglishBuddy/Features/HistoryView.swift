import SwiftUI

private struct ConversationThreadSummary: Identifiable {
    let id: String
    let sessions: [ConversationSession]
    let threadState: ConversationThreadState?

    var latestSession: ConversationSession {
        sessions[0]
    }

    var character: CharacterProfile {
        CharacterCatalog.profile(for: latestSession.characterID)
    }

    var scene: CharacterScene {
        CharacterCatalog.scene(for: latestSession.sceneID, characterID: latestSession.characterID)
    }

    var language: LanguageProfile {
        LanguageCatalog.profile(for: latestSession.languageProfileID)
    }

    var scenario: ScenarioPreset? {
        latestSession.scenarioID.map { ScenarioCatalog.preset(for: $0, mode: latestSession.mode) }
    }

    var threadSummary: String {
        if let summary = threadState?.summary.trimmingCharacters(in: .whitespacesAndNewlines), summary.isEmpty == false {
            return summary
        }
        let summary = latestSession.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty == false {
            return summary
        }
        return latestSession.turns.last?.text ?? "Continue this thread from the most recent local exchange."
    }

    var threadMission: String? {
        if let mission = threadState?.nextMission, mission.isEmpty == false {
            return mission
        }
        if let mission = threadState?.currentMission, mission.isEmpty == false {
            return mission
        }
        if let mission = latestSession.learningPlanSnapshot?.mission, mission.isEmpty == false {
            return mission
        }
        return nil
    }

    var continuationCue: String? {
        threadState?.continuationCue
    }

    var summaryLead: String {
        "\(language.displayName) thread • \(sessions.count) local sessions"
    }
}

struct HistoryView: View {
    let container: AppContainer
    @ObservedObject private var rootState: RootViewModel
    @State private var selectedThread: ConversationThreadSummary?

    init(container: AppContainer) {
        self.container = container
        _rootState = ObservedObject(wrappedValue: container.rootState)
    }

    private var sessions: [ConversationSession] {
        rootState.snapshot.sessions.sorted { $0.startedAt > $1.startedAt }
    }

    private var visualStyle: VideoCallVisualStyle {
        rootState.snapshot.companionSettings.visualStyle
    }

    private var threads: [ConversationThreadSummary] {
        let threadStateByID = Dictionary(uniqueKeysWithValues: rootState.snapshot.threadStates.map { ($0.id, $0) })
        return Dictionary(grouping: sessions, by: \.continuationThreadID)
            .map { threadID, groupedSessions in
                ConversationThreadSummary(
                    id: threadID,
                    sessions: groupedSessions.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) },
                    threadState: threadStateByID[threadID]
                )
            }
            .sorted { ($0.latestSession.endedAt ?? $0.latestSession.startedAt) > ($1.latestSession.endedAt ?? $1.latestSession.startedAt) }
    }

    var body: some View {
        ZStack {
            AppCanvasBackground(style: .history)

            if threads.isEmpty {
                ContentUnavailableView(
                    "No threads yet",
                    systemImage: "video.badge.waveform",
                    description: Text("Your local character threads, missions, and debriefs will appear here after the first call.")
                )
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        historyHero

                        ForEach(threads) { thread in
                            ThreadHistoryCard(
                                thread: thread,
                                openAction: {
                                    selectedThread = thread
                                },
                                continueAction: {
                                    Task { await continueThread(thread.latestSession) }
                                }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("History")
        .sheet(item: $selectedThread) { thread in
            ThreadDetailView(
                thread: thread,
                visualStyle: visualStyle,
                continueAction: { session in
                    selectedThread = nil
                    Task { await continueThread(session) }
                }
            )
        }
    }

    private var historyHero: some View {
        let activeCharacters = Set(threads.map(\.latestSession.characterID)).count
        let completedTutor = threads.filter { $0.latestSession.mode == .tutor }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("All threads stay on device, so each companion keeps the latest mission, cue, and scene ready to resume.")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                HistoryMetric(title: "Threads", value: "\(threads.count)")
                HistoryMetric(title: "Characters", value: "\(activeCharacters)")
                HistoryMetric(title: "Tutor Threads", value: "\(completedTutor)")
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.17, green: 0.30, blue: 0.45), Color(red: 0.86, green: 0.43, blue: 0.27)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func continueThread(_ session: ConversationSession) async {
        do {
            try await rootState.updateCompanionSettings { settings in
                settings.selectedCharacterID = CharacterCatalog.profile(for: session.characterID).id
                settings.selectedSceneID = CharacterCatalog.scene(for: session.sceneID, characterID: session.characterID).id
                settings.conversationLanguageID = session.languageProfileID
                settings.selectedVoiceBundleID = session.voiceBundleID
                settings.warmupCompleted = true
            }
            rootState.showingHistory = false
            await rootState.startCall(
                session.mode,
                preferredScenarioID: session.scenarioID,
                continuationAnchor: session
            )
        } catch {
            rootState.globalError = error.localizedDescription
        }
    }
}

private struct HistoryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

private struct ThreadHistoryCard: View {
    let thread: ConversationThreadSummary
    let openAction: () -> Void
    let continueAction: () -> Void

    private var preview: some View {
        CharacterStageSurface(
            character: thread.character,
            scene: thread.scene,
            visualStyle: .natural,
            emphasis: .preview,
            surfaceKind: .historyPreview,
            size: CGSize(width: 92, height: 118),
            isAnimated: false,
            showsBackdrop: false,
            groundShadowWidth: 64,
            groundShadowHeight: 10,
            groundShadowBlur: 7
        )
        .frame(width: 92, height: 118)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.93, blue: 0.96),
                            Color(red: 0.98, green: 0.95, blue: 0.91)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(thread.character.displayName) • \(thread.latestSession.mode.title)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.22))

                    HStack(spacing: 8) {
                        ThreadMetaBadge(text: thread.scene.title)
                        ThreadMetaBadge(text: thread.language.displayName)
                    }

                    Text(thread.summaryLead)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color(red: 0.48, green: 0.42, blue: 0.38))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(thread.latestSession.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)

                    preview
                }
            }

            if let scenario = thread.scenario {
                Text(scenario.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.50, green: 0.24, blue: 0.10))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.99, green: 0.92, blue: 0.85))
                    )
            }

            Text(thread.threadSummary)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(4)

            if let mission = thread.threadMission {
                Text(mission)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.31, green: 0.28, blue: 0.34))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.94, blue: 0.91))
                    )
            }

            if let continuationCue = thread.continuationCue, continuationCue.isEmpty == false {
                Text(continuationCue)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(red: 0.44, green: 0.40, blue: 0.39))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(red: 0.98, green: 0.95, blue: 0.91))
                    )
            }

            HStack(spacing: 8) {
                ThreadMetaBadge(text: durationText, systemImage: "clock")
                ThreadMetaBadge(text: "\(thread.latestSession.turns.count) turns", systemImage: "text.bubble")
                ThreadMetaBadge(text: "\(thread.sessions.count) sessions", systemImage: "square.stack")
            }

            if let goalSummary = thread.latestSession.feedbackReport?.goalCompletionSummary, goalSummary.isEmpty == false {
                Text(goalSummary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(red: 0.29, green: 0.26, blue: 0.31))
            }

            if let nextTheme = thread.latestSession.feedbackReport?.nextThemeSuggestion, nextTheme.isEmpty == false {
                Text(nextTheme)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.88, green: 0.43, blue: 0.27))
            }

            HStack(spacing: 10) {
                Button("Review Thread", action: openAction)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppTheme.canvasLift)
                    )

                Button(action: continueAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill")
                        Text("Continue Thread")
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.92, green: 0.42, blue: 0.27))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .surfaceCard()
    }

    private var durationText: String {
        let totalMinutes = Int(thread.latestSession.duration / 60)
        if totalMinutes > 0 {
            return "\(totalMinutes) min"
        }
        return "<1 min"
    }
}

private struct ThreadMetaBadge: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(text)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(Color(red: 0.44, green: 0.40, blue: 0.39))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color(red: 0.96, green: 0.94, blue: 0.91))
        )
    }
}

private struct ThreadDetailView: View {
    let thread: ConversationThreadSummary
    let visualStyle: VideoCallVisualStyle
    let continueAction: (ConversationSession) -> Void

    @State private var selectedSession: ConversationSession?

    var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackground(style: .history)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            HistoryCharacterPreview(
                                character: thread.character,
                                scene: thread.scene,
                                visualStyle: visualStyle
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 2)

                            Text("\(thread.character.displayName) • \(thread.scenario?.title ?? thread.latestSession.mode.title)")
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.82))

                            Text(thread.threadSummary)
                                .font(.system(.title3, design: .rounded, weight: .black))
                                .foregroundStyle(.white)

                            if let mission = thread.threadMission {
                                DetailBadge(text: mission)
                            }

                            if let continuationCue = thread.continuationCue, continuationCue.isEmpty == false {
                                Text(continuationCue)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.84))
                            }

                            HStack(spacing: 10) {
                                DetailBadge(text: thread.scene.title)
                                DetailBadge(text: thread.language.displayName)
                                DetailBadge(text: "\(thread.sessions.count) sessions")
                            }

                            Button {
                                continueAction(thread.latestSession)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "video.fill")
                                    Text("Continue This Thread")
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                    Spacer()
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(Color.black.opacity(0.24))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(22)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.15, green: 0.21, blue: 0.33), Color(red: 0.58, green: 0.33, blue: 0.24)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )

                        VStack(alignment: .leading, spacing: 12) {
                            AppSectionHeader(
                                eyebrow: "Timeline",
                                title: "Sessions in this thread",
                                subtitle: "Open any saved turn to review the local transcript and continue from that moment."
                            )

                            ForEach(thread.sessions) { session in
                                Button {
                                    selectedSession = session
                                } label: {
                                    SessionThreadCard(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .detailPanel()
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Thread")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedSession) { session in
                SessionDetailView(
                    session: session,
                    visualStyle: visualStyle,
                    continueAction: {
                        selectedSession = nil
                        continueAction(session)
                    }
                )
            }
        }
    }
}

private struct SessionThreadCard: View {
    let session: ConversationSession

    private var scenario: ScenarioPreset? {
        session.scenarioID.map { ScenarioCatalog.preset(for: $0, mode: session.mode) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0.49, green: 0.43, blue: 0.38))
                Spacer()
                Text(session.mode.title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0.50, green: 0.24, blue: 0.10))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.99, green: 0.92, blue: 0.85))
                    )
            }

            if let scenario {
                Text(scenario.title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.22))
            }

            Text(session.summary.isEmpty ? "Session saved locally." : session.summary)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.98, green: 0.96, blue: 0.94))
        )
    }
}

private struct SessionDetailView: View {
    let session: ConversationSession
    let visualStyle: VideoCallVisualStyle
    var continueAction: (() -> Void)? = nil

    private var character: CharacterProfile { CharacterCatalog.profile(for: session.characterID) }
    private var scene: CharacterScene { CharacterCatalog.scene(for: session.sceneID, characterID: character.id) }
    private var scenario: ScenarioPreset? {
        session.scenarioID.map { ScenarioCatalog.preset(for: $0, mode: session.mode) }
    }
    private var language: LanguageProfile { LanguageCatalog.profile(for: session.languageProfileID) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackground(style: .history)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        detailHero
                        missionSection
                        feedbackSection
                        transcriptSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle(session.mode.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var detailHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HistoryCharacterPreview(
                character: character,
                scene: scene,
                visualStyle: visualStyle
            )
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)

            Text("\(character.displayName) in \(scene.title)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.82))

            Text(session.summary.isEmpty ? "This conversation finished locally and is ready to review." : session.summary)
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                DetailBadge(text: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let scenario {
                    DetailBadge(text: scenario.title)
                }
                DetailBadge(text: language.displayName)
                DetailBadge(text: "\(session.turns.count) turns")
            }

            if let continueAction {
                Button(action: continueAction) {
                    HStack(spacing: 10) {
                        Image(systemName: "video.fill")
                        Text("Continue From This Session")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.black.opacity(0.24))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.21, blue: 0.33), Color(red: 0.58, green: 0.33, blue: 0.24)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var missionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mission")
                .font(.system(.title3, design: .rounded, weight: .bold))

            if let learningPlan = session.learningPlanSnapshot {
                DetailRow(title: learningPlan.title, content: learningPlan.mission)
                DetailRow(title: "Checkpoint", content: learningPlan.checkpoint)
                DetailRow(title: "Success Signal", content: learningPlan.successSignal)
            } else if let scenario {
                DetailRow(title: scenario.title, content: scenario.summary)
            } else {
                DetailRow(title: "Mode", content: session.mode.subtitle)
            }
        }
        .detailPanel()
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feedback")
                .font(.system(.title3, design: .rounded, weight: .bold))

            if let feedback = session.feedbackReport {
                if feedback.goalCompletionSummary.isEmpty == false {
                    DetailRow(title: "Outcome", content: feedback.goalCompletionSummary)
                }
                if feedback.nextMission.isEmpty == false {
                    DetailRow(title: "Next Mission", content: feedback.nextMission)
                }
                if feedback.nextThemeSuggestion.isEmpty == false {
                    DetailRow(title: "Next Theme", content: feedback.nextThemeSuggestion)
                }
                if feedback.continuationCue.isEmpty == false {
                    DetailRow(title: "Continuation Cue", content: feedback.continuationCue)
                }
                if feedback.carryOverVocabulary.isEmpty == false {
                    DetailRow(title: "Carry-over Vocabulary", content: feedback.carryOverVocabulary.joined(separator: " • "))
                }
                if feedback.pronunciationHighlights.isEmpty == false {
                    DetailRow(title: "Pronunciation Highlights", content: feedback.pronunciationHighlights.joined(separator: " • "))
                }
            } else {
                Text("No feedback saved for this session yet.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .detailPanel()
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcript")
                .font(.system(.title3, design: .rounded, weight: .bold))

            ForEach(session.turns) { turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.role == .user ? "You" : character.displayName)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(turn.role == .user ? Color(red: 0.18, green: 0.42, blue: 0.37) : Color(red: 0.50, green: 0.24, blue: 0.10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(
                                    turn.role == .user
                                        ? Color(red: 0.83, green: 0.93, blue: 0.89)
                                        : Color(red: 0.99, green: 0.92, blue: 0.85)
                                )
                        )
                    Text(turn.text)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.22))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            turn.role == .user
                                ? Color(red: 0.89, green: 0.96, blue: 0.93)
                                : Color(red: 0.99, green: 0.96, blue: 0.93)
                        )
                )
            }
        }
        .detailPanel()
    }
}

private struct HistoryCharacterPreview: View, Equatable {
    let character: CharacterProfile
    let scene: CharacterScene
    let visualStyle: VideoCallVisualStyle

    var body: some View {
        CharacterStageSurface(
            character: character,
            scene: scene,
            visualStyle: visualStyle,
            emphasis: .preview,
            surfaceKind: .historyPreview,
            size: CGSize(width: 164, height: 212),
            isAnimated: false,
            showsBackdrop: false,
            shadowColor: .black.opacity(0.18),
            shadowRadius: 22,
            shadowYOffset: 12,
            groundShadowWidth: 112
        )
    }
}

private struct DetailBadge: View {
    let text: String

    var body: some View {
        AppCapsuleBadge(text: text, tint: Color.white, foreground: .white, backgroundOpacity: 0.12)
    }
}

private struct DetailRow: View {
    let title: String
    let content: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color(red: 0.31, green: 0.27, blue: 0.32))
            Text(content)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.22))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.98, green: 0.96, blue: 0.94))
        )
    }

    var body: some View { bodyView }
}

private extension View {
    func detailPanel() -> some View {
        surfaceCard()
    }
}
