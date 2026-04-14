import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var selectedSession: ConversationSession?

    private var sessions: [ConversationSession] {
        container.rootState.snapshot.sessions.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        ZStack {
            AppCanvasBackground()

            if sessions.isEmpty {
                ContentUnavailableView(
                    "No calls yet",
                    systemImage: "video.badge.waveform",
                    description: Text("Your offline video-style conversations, missions, and debriefs will appear here after the first call.")
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        historyHero

                        ForEach(sessions) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                SessionHistoryCard(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("History")
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
    }

    private var historyHero: some View {
        let completedTutor = sessions.filter { $0.mode == .tutor }.count
        let completedChat = sessions.filter { $0.mode == .chat }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Character memory stays on device, so every finished call keeps its scene, mission, and coaching trail.")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 10) {
                HistoryMetric(title: "Total Calls", value: "\(sessions.count)")
                HistoryMetric(title: "Chat", value: "\(completedChat)")
                HistoryMetric(title: "Tutor", value: "\(completedTutor)")
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
                .foregroundStyle(.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }
}

private struct SessionHistoryCard: View {
    let session: ConversationSession

    private var character: CharacterProfile { CharacterCatalog.profile(for: session.characterID) }
    private var scene: CharacterScene { CharacterCatalog.scene(for: session.sceneID, characterID: character.id) }
    private var scenario: ScenarioPreset? {
        session.scenarioID.map { ScenarioCatalog.preset(for: $0, mode: session.mode) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(character.displayName) • \(session.mode.title)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.22))
                    Text(scene.title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color(red: 0.49, green: 0.43, blue: 0.38))
                }

                Spacer()

                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let scenario {
                Text(scenario.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.89, green: 0.43, blue: 0.27))
            }

            Text(session.summary.isEmpty ? "This conversation finished locally and is ready to review." : session.summary)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let learningPlan = session.learningPlanSnapshot {
                Text(learningPlan.mission)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(red: 0.31, green: 0.28, blue: 0.34))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.94, blue: 0.91))
                    )
            }

            HStack {
                Label(durationText, systemImage: "clock")
                Spacer()
                Label("\(session.turns.count) turns", systemImage: "text.bubble")
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(Color(red: 0.44, green: 0.40, blue: 0.39))

            if let goalSummary = session.feedbackReport?.goalCompletionSummary, goalSummary.isEmpty == false {
                Text(goalSummary)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color(red: 0.29, green: 0.26, blue: 0.31))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.94))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private var durationText: String {
        let totalMinutes = Int(session.duration / 60)
        if totalMinutes > 0 {
            return "\(totalMinutes) min"
        }
        return "<1 min"
    }
}

private struct SessionDetailView: View {
    let session: ConversationSession

    private var character: CharacterProfile { CharacterCatalog.profile(for: session.characterID) }
    private var scene: CharacterScene { CharacterCatalog.scene(for: session.sceneID, characterID: character.id) }
    private var scenario: ScenarioPreset? {
        session.scenarioID.map { ScenarioCatalog.preset(for: $0, mode: session.mode) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackground()

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
                DetailBadge(text: "\(session.turns.count) turns")
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
                        .foregroundStyle(turn.role == .user ? Color(red: 0.23, green: 0.48, blue: 0.43) : Color(red: 0.88, green: 0.43, blue: 0.27))
                    Text(turn.text)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.22))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(turn.role == .user ? Color(red: 0.89, green: 0.96, blue: 0.93) : Color.white.opacity(0.94))
                )
            }
        }
        .detailPanel()
    }
}

private struct DetailBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.14)))
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
        padding(18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            }
    }
}
