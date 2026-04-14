import SwiftUI

struct FeedbackView: View {
    let report: FeedbackReport
    let mode: ConversationMode
    let character: CharacterProfile?
    let scenario: ScenarioPreset?
    let learningPlan: LearningFocusPlan?
    let dismissAction: () -> Void

    init(
        report: FeedbackReport,
        mode: ConversationMode,
        character: CharacterProfile? = nil,
        scenario: ScenarioPreset? = nil,
        learningPlan: LearningFocusPlan? = nil,
        dismissAction: @escaping () -> Void
    ) {
        self.report = report
        self.mode = mode
        self.character = character
        self.scenario = scenario
        self.learningPlan = learningPlan
        self.dismissAction = dismissAction
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppCanvasBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        heroSummary
                        missionDashboard
                        correctionBoard
                        languageCarryOver
                        nextCallBoard
                    }
                    .padding(20)
                }
            }
            .navigationTitle(mode == .tutor ? "Call Debrief" : "Session Debrief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismissAction)
                }
            }
        }
    }

    private var heroSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(character?.displayName ?? (mode == .tutor ? "Your tutor" : "Your companion"))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.8))
                    Text(report.goalCompletionSummary)
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                    Text(heroSubtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 8) {
                    FeedbackBadge(text: mode.title)
                    FeedbackBadge(text: report.generatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let scenarioTitle = scenario?.title {
                Label(scenarioTitle, systemImage: "flag.checkered.2.crossed")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }

            if report.nextMission.isEmpty == false {
                Text(report.nextMission)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: mode == .tutor
                            ? [Color(red: 0.19, green: 0.24, blue: 0.36), Color(red: 0.64, green: 0.31, blue: 0.22)]
                            : [Color(red: 0.16, green: 0.31, blue: 0.46), Color(red: 0.89, green: 0.46, blue: 0.27)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var missionDashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mission Dashboard")
                .font(.system(.title3, design: .rounded, weight: .bold))

            if let learningPlan {
                DashboardRow(title: learningPlan.title, content: learningPlan.mission)
                DashboardRow(title: "Checkpoint", content: learningPlan.checkpoint)
                DashboardRow(title: "Success Signal", content: learningPlan.successSignal)
            } else {
                DashboardRow(title: "Mission", content: report.goalCompletionSummary)
            }

            if report.pronunciationHighlights.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pronunciation Focus")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    TagCloud(items: report.pronunciationHighlights, style: .mint)
                }
            }
        }
        .panelStyle()
    }

    private var correctionBoard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Call Notes")
                .font(.system(.title3, design: .rounded, weight: .bold))

            CorrectionGroup(title: "Grammar", items: report.grammarIssues, tint: Color.blue)
            CorrectionGroup(title: "Vocabulary", items: report.vocabularySuggestions, tint: Color.orange)
            CorrectionGroup(title: "Pronunciation", items: report.pronunciationTips, tint: Color.green)
        }
        .panelStyle()
    }

    private var languageCarryOver: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Carry Forward")
                .font(.system(.title3, design: .rounded, weight: .bold))

            DashboardRow(
                title: mode == .tutor ? "Reusable Expressions" : "Smooth Phrases",
                content: report.frequentExpressions.isEmpty ? "No phrases captured yet." : report.frequentExpressions.joined(separator: " • ")
            )

            if report.carryOverVocabulary.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vocabulary Queue")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    TagCloud(items: report.carryOverVocabulary, style: .amber)
                }
            }
        }
        .panelStyle()
    }

    private var nextCallBoard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next Call")
                .font(.system(.title3, design: .rounded, weight: .bold))

            DashboardRow(title: "Recommended next mission", content: report.nextMission)

            DashboardRow(
                title: mode == .tutor ? "Follow-up drill" : "Follow-up topic",
                content: report.nextTopicSuggestions.isEmpty
                    ? "Repeat the same character and add one more vivid detail."
                    : report.nextTopicSuggestions.joined(separator: " • ")
            )
        }
        .panelStyle()
    }

    private var heroSubtitle: String {
        if let scenario {
            return "This \(mode.title.lowercased()) call used the \(scenario.title.lowercased()) setup and stored a clearer next step."
        }
        return mode == .tutor
            ? "Tutor mode pushes one objective at a time and saves a sharper next move."
            : "Chat mode keeps the rhythm natural, then saves the parts worth carrying into the next call."
    }
}

private struct FeedbackBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.16)))
    }
}

private struct DashboardRow: View {
    let title: String
    let content: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color(red: 0.28, green: 0.25, blue: 0.31))
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

private struct CorrectionGroup: View {
    let title: String
    let items: [CorrectionEvent]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))

            if items.isEmpty {
                Text("No items saved for this section.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.suggestion)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color(red: 0.17, green: 0.15, blue: 0.22))
                        Text(item.explanation)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Color(red: 0.40, green: 0.36, blue: 0.36))
                        if item.source.isEmpty == false {
                            Text("From: \(item.source)")
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .foregroundStyle(tint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(tint.opacity(0.1))
                    )
                }
            }
        }
    }
}

private struct TagCloud: View {
    enum Style {
        case mint
        case amber

        var foreground: Color {
            switch self {
            case .mint:
                return Color(red: 0.15, green: 0.40, blue: 0.33)
            case .amber:
                return Color(red: 0.56, green: 0.35, blue: 0.07)
            }
        }

        var background: Color {
            switch self {
            case .mint:
                return Color(red: 0.88, green: 0.96, blue: 0.92)
            case .amber:
                return Color(red: 0.99, green: 0.93, blue: 0.82)
            }
        }
    }

    let items: [String]
    let style: Style

    var body: some View {
        FlexibleRow(items, spacing: 8) { item in
            Text(item)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(style.foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Capsule().fill(style.background))
        }
    }
}

private struct FlexibleRow<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    @ViewBuilder let content: (Data.Element) -> Content

    init(_ data: Data, spacing: CGFloat = 10, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func panelStyle() -> some View {
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
