import Combine
import SwiftUI

@MainActor
struct CallPresentationContext {
    let character: CharacterProfile
    let scene: CharacterScene
    let scenario: ScenarioPreset?
    let visualStyle: VideoCallVisualStyle
    let launchingMode: ConversationMode

    static func resolve(rootState: RootViewModel, orchestrator: ConversationOrchestrator) -> CallPresentationContext {
        let session = orchestrator.activeSession
        let settings = rootState.snapshot.companionSettings
        let character = CharacterCatalog.profile(for: session?.characterID ?? settings.selectedCharacterID)
        let scene = CharacterCatalog.scene(
            for: session?.sceneID ?? settings.selectedSceneID,
            characterID: character.id
        )
        let mode = session?.mode ?? rootState.launchingMode
        let scenario = session?.scenarioID.flatMap { ScenarioCatalog.preset(for: $0, mode: mode) }

        return CallPresentationContext(
            character: character,
            scene: scene,
            scenario: scenario,
            visualStyle: settings.visualStyle,
            launchingMode: mode
        )
    }
}

private struct CallHeaderState: Equatable {
    let phase: CallPhase
    let activeMode: ConversationMode?
    let inputMode: CallInputMode
}

private struct CallStageState: Equatable {
    let avatarState: AvatarState
    let audioLevel: Double
    let lipSyncFrame: LipSyncFrame
}

private struct CallSubtitleState: Equatable {
    let phase: CallPhase
    let liveUserTranscript: String
    let liveAssistantTranscript: String
    let visibleTurns: [ConversationTurn]
}

@MainActor
private final class CallHeaderObserver: ObservableObject {
    @Published private(set) var state: CallHeaderState

    private var cancellable: AnyCancellable?

    init(orchestrator: ConversationOrchestrator) {
        state = CallHeaderState(
            phase: orchestrator.phase,
            activeMode: orchestrator.activeMode,
            inputMode: orchestrator.inputMode
        )

        cancellable = Publishers.CombineLatest3(
            orchestrator.$phase,
            orchestrator.$activeMode,
            orchestrator.$inputMode
        )
        .map { phase, activeMode, inputMode in
            CallHeaderState(phase: phase, activeMode: activeMode, inputMode: inputMode)
        }
        .removeDuplicates()
        .sink { [weak self] newState in
            self?.state = newState
        }
    }
}

@MainActor
private final class CallStageObserver: ObservableObject {
    @Published private(set) var state: CallStageState

    private var cancellable: AnyCancellable?

    init(orchestrator: ConversationOrchestrator) {
        state = CallStageState(
            avatarState: orchestrator.avatarState,
            audioLevel: orchestrator.audioLevel,
            lipSyncFrame: orchestrator.lipSyncFrame
        )

        cancellable = Publishers.CombineLatest3(
            orchestrator.$avatarState,
            orchestrator.$audioLevel,
            orchestrator.$lipSyncFrame
        )
        .map { avatarState, audioLevel, lipSyncFrame in
            CallStageState(avatarState: avatarState, audioLevel: audioLevel, lipSyncFrame: lipSyncFrame)
        }
        .removeDuplicates()
        .sink { [weak self] newState in
            self?.state = newState
        }
    }
}

@MainActor
private final class CallSubtitleObserver: ObservableObject {
    @Published private(set) var state: CallSubtitleState

    private var cancellable: AnyCancellable?

    init(orchestrator: ConversationOrchestrator) {
        state = CallSubtitleState(
            phase: orchestrator.phase,
            liveUserTranscript: orchestrator.liveUserTranscript,
            liveAssistantTranscript: orchestrator.liveAssistantTranscript,
            visibleTurns: orchestrator.visibleTurns
        )

        cancellable = Publishers.CombineLatest4(
            orchestrator.$phase,
            orchestrator.$liveUserTranscript,
            orchestrator.$liveAssistantTranscript,
            orchestrator.$visibleTurns
        )
        .map { phase, liveUserTranscript, liveAssistantTranscript, visibleTurns in
            CallSubtitleState(
                phase: phase,
                liveUserTranscript: liveUserTranscript,
                liveAssistantTranscript: liveAssistantTranscript,
                visibleTurns: visibleTurns
            )
        }
        .removeDuplicates()
        .sink { [weak self] newState in
            self?.state = newState
        }
    }
}

@MainActor
private final class TranscriptObserver: ObservableObject {
    @Published private(set) var visibleTurns: [ConversationTurn]

    private var cancellable: AnyCancellable?

    init(orchestrator: ConversationOrchestrator) {
        visibleTurns = orchestrator.visibleTurns
        cancellable = orchestrator.$visibleTurns
            .removeDuplicates()
            .sink { [weak self] turns in
                self?.visibleTurns = turns
            }
    }
}

@MainActor
struct CallView: View {
    @ObservedObject var performanceGovernor: PerformanceGovernor
    let rootState: RootViewModel
    let orchestrator: ConversationOrchestrator
    let context: CallPresentationContext

    @Environment(\.dismiss) private var dismiss
    @State private var isTextInputActive = false
    @State private var subtitleMode: SubtitleOverlayMode = .collapsed

    var body: some View {
        GeometryReader { proxy in
            let layout = CallStageLayout(
                performanceProfile: performanceGovernor.profile,
                containerSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                subtitleMode: subtitleMode
            )
            ZStack {
                CallBackground(scene: context.scene)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    CallHeaderPane(orchestrator: orchestrator, context: context)
                        .padding(.horizontal, layout.horizontalPadding)
                        .padding(.top, layout.headerTopPadding)

                    CallStagePane(
                        orchestrator: orchestrator,
                        context: context,
                        textInputActive: isTextInputActive,
                        layout: layout,
                        allowsContinuousAnimation: performanceGovernor.profile.allowsContinuousHeroAnimation
                    )
                    .frame(maxWidth: .infinity, maxHeight: layout.stageContainerHeight, alignment: .top)

                    Spacer(minLength: 0)
                }

                SubtitleOverlayPane(
                    orchestrator: orchestrator,
                    context: context,
                    layout: layout,
                    subtitleMode: $subtitleMode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                CallBottomControls(
                    orchestrator: orchestrator,
                    rootState: rootState,
                    textInputActive: $isTextInputActive,
                    subtitleMode: $subtitleMode
                )
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.bottom, layout.controlsBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .foregroundStyle(.white)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: Binding(
            get: { subtitleMode == .fullTranscript },
            set: { newValue in
                if newValue == false {
                    subtitleMode = .expanded
                }
            }
        )) {
            TranscriptSheet(orchestrator: orchestrator, assistantName: context.character.displayName)
        }
        .onDisappear {
            if rootState.showingCall {
                rootState.showingCall = false
            }
        }
    }
}

@MainActor
private struct CallHeaderPane: View {
    let context: CallPresentationContext
    @StateObject private var observer: CallHeaderObserver

    init(orchestrator: ConversationOrchestrator, context: CallPresentationContext) {
        self.context = context
        _observer = StateObject(wrappedValue: CallHeaderObserver(orchestrator: orchestrator))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.character.displayName)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text(callStatusText(observer.state.phase))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                StatusPill(text: callModeLabel)
            }

            Text(headerMetaLine)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var callModeLabel: String {
        observer.state.activeMode?.title ?? context.launchingMode.title
    }

    private var headerMetaLine: String {
        let details = [
            context.scene.title,
            context.scenario?.title,
            interruptibilityText(for: observer.state.phase, inputMode: observer.state.inputMode)
        ].compactMap { $0 }.filter { $0.isEmpty == false }

        return details.joined(separator: "  •  ")
    }
}

@MainActor
private struct CallStagePane: View {
    let context: CallPresentationContext
    let textInputActive: Bool
    let layout: CallStageLayout
    let allowsContinuousAnimation: Bool
    @StateObject private var observer: CallStageObserver

    init(
        orchestrator: ConversationOrchestrator,
        context: CallPresentationContext,
        textInputActive: Bool,
        layout: CallStageLayout,
        allowsContinuousAnimation: Bool
    ) {
        self.context = context
        self.textInputActive = textInputActive
        self.layout = layout
        self.allowsContinuousAnimation = allowsContinuousAnimation
        _observer = StateObject(wrappedValue: CallStageObserver(orchestrator: orchestrator))
    }

    var body: some View {
        CharacterCallHeroSurface(
            character: context.character,
            scene: context.scene,
            visualStyle: context.visualStyle,
            state: observer.state.avatarState,
            audioLevel: observer.state.audioLevel,
            lipSyncFrame: observer.state.lipSyncFrame,
            stageSize: layout.stageSize,
            verticalOffset: layout.stageVerticalOffset,
            isAnimated: allowsContinuousAnimation && textInputActive == false
        )
        .frame(width: layout.stageContainerSize.width, height: layout.stageContainerHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

@MainActor
private struct SubtitleOverlayPane: View {
    let orchestrator: ConversationOrchestrator
    let context: CallPresentationContext
    let layout: CallStageLayout
    @Binding var subtitleMode: SubtitleOverlayMode
    @State private var dragOffset: CGFloat = 0
    @StateObject private var observer: CallSubtitleObserver

    init(
        orchestrator: ConversationOrchestrator,
        context: CallPresentationContext,
        layout: CallStageLayout,
        subtitleMode: Binding<SubtitleOverlayMode>
    ) {
        self.orchestrator = orchestrator
        self.context = context
        self.layout = layout
        _subtitleMode = subtitleMode
        _observer = StateObject(wrappedValue: CallSubtitleObserver(orchestrator: orchestrator))
    }

    var body: some View {
        let display = subtitleDisplay(state: observer.state, assistantName: context.character.displayName)
        let panelHeight = layout.subtitlePanelHeight(dragOffset: dragOffset)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 14) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.speakerTitle)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(display.accent.opacity(0.92))
                        subtitleContent(display: display)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Button {
                        subtitleMode = .fullTranscript
                        dragOffset = 0
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.94))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.black.opacity(0.26)))
                    }
                    .buttonStyle(.plain)
                }

                if display.supportingText.isEmpty == false {
                    Text(display.supportingText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(layout.performanceProfile.prefersOpaqueSubtitleOverlay ? 0.90 : 0.82))
                        .lineLimit(subtitleMode == .collapsed ? 2 : 3)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: panelHeight, maxHeight: panelHeight, alignment: .top)
            .background(overlayBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(layout.performanceProfile.prefersOpaqueSubtitleOverlay ? 0.14 : 0.09), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, layout.horizontalPadding - 2)
            .padding(.bottom, layout.subtitleBottomPadding)
            .offset(y: layout.overlayRestingOffset(dragOffset: dragOffset))
            .animation(.spring(response: 0.32, dampingFraction: 0.84), value: subtitleMode)
            .onAppear {
                orchestrator.syncSubtitleOverlay(
                    mode: subtitleMode,
                    dragOffset: dragOffset,
                    currentHeight: panelHeight
                )
            }
            .onChange(of: subtitleMode) { _, newValue in
                orchestrator.syncSubtitleOverlay(
                    mode: newValue,
                    dragOffset: dragOffset,
                    currentHeight: panelHeight
                )
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        handleOverlayDragEnded(
                            translation: value.translation.height,
                            predictedTranslation: value.predictedEndTranslation.height
                        )
                    }
            )
        }
    }

    @ViewBuilder
    private func subtitleContent(
        display: (speakerTitle: String, subtitle: String, supportingText: String, accent: Color)
    ) -> some View {
        if subtitleMode == .collapsed {
            Text(display.subtitle)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(showsIndicators: true) {
                Text(display.subtitle)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func handleOverlayDragEnded(
        translation: CGFloat,
        predictedTranslation: CGFloat
    ) {
        let startedAt = Date()
        let currentHeight = subtitleMode == .collapsed ? layout.collapsedSubtitleHeight : layout.expandedSubtitleHeight
        let projectedHeight = currentHeight - predictedTranslation
        let midpoint = (layout.collapsedSubtitleHeight + layout.expandedSubtitleHeight) / 2

        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            subtitleMode = projectedHeight >= midpoint || translation < -36 ? .expanded : .collapsed
            dragOffset = 0
        }
        DispatchQueue.main.async {
            let elapsed = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
            orchestrator.recordSubtitleDragResponse(milliseconds: elapsed)
            orchestrator.syncSubtitleOverlay(
                mode: subtitleMode,
                dragOffset: dragOffset,
                currentHeight: subtitleMode == .collapsed ? layout.collapsedSubtitleHeight : layout.expandedSubtitleHeight
            )
        }
    }

    @ViewBuilder
    private var overlayBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        shape
            .fill(layout.performanceProfile.prefersOpaqueSubtitleOverlay ? Color.black.opacity(0.82) : Color.black.opacity(0.60))
            .overlay {
                if layout.performanceProfile.prefersOpaqueSubtitleOverlay == false {
                    shape
                        .fill(.ultraThinMaterial)
                        .opacity(0.78)
                }
            }
    }
}

@MainActor
private struct CallBottomControls: View {
    let orchestrator: ConversationOrchestrator
    let rootState: RootViewModel
    @Binding var textInputActive: Bool
    @Binding var subtitleMode: SubtitleOverlayMode
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var focusRequestedAt: Date?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            inlineComposer

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        subtitleMode = subtitleMode == .collapsed ? .expanded : .collapsed
                    }
                } label: {
                    Label(
                        subtitleMode == .collapsed ? "Expand Captions" : "Collapse Captions",
                        systemImage: subtitleMode == .collapsed ? "captions.bubble" : "captions.bubble.fill"
                    )
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.black.opacity(0.24))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    Task {
                        await rootState.finishCall()
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "phone.down.fill")
                        Text("End")
                    }
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(red: 0.89, green: 0.23, blue: 0.24))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            textInputActive = isFocused
            guard isFocused, let requestedAt = focusRequestedAt else { return }
            let elapsed = max(0, Int(Date().timeIntervalSince(requestedAt) * 1000))
            orchestrator.recordKeyboardOpenLatency(milliseconds: elapsed)
            focusRequestedAt = nil
        }
        .onDisappear {
            textInputActive = false
        }
    }

    private var inlineComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Type a message", text: $draft, axis: .vertical)
                .focused($isTextFieldFocused)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit(sendDraft)
                .onTapGesture {
                    if isTextFieldFocused == false {
                        focusRequestedAt = .now
                    }
                }

            Button(action: sendDraft) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.white.opacity(0.28)
                            : Color(red: 1.0, green: 0.78, blue: 0.58)
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func sendDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        draft = ""
        Task {
            await orchestrator.sendTextFallback(trimmed)
        }
    }
}

@MainActor
private struct CallBackground: View {
    let scene: CharacterScene

    var body: some View {
        ZStack {
            switch scene.id {
            case "study":
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.10, blue: 0.17), Color(red: 0.17, green: 0.18, blue: 0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case "nightcity":
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.08, blue: 0.16), Color(red: 0.14, green: 0.08, blue: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            default:
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.11, blue: 0.18), Color(red: 0.24, green: 0.16, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 280, height: 280)
                .blur(radius: 18)
                .offset(x: 120, y: -220)

            Circle()
                .fill(Color.orange.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 26)
                .offset(x: -140, y: 260)
        }
    }
}

@MainActor
private struct StatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

@MainActor
private struct TranscriptSheet: View {
    let assistantName: String
    @StateObject private var observer: TranscriptObserver

    init(orchestrator: ConversationOrchestrator, assistantName: String) {
        self.assistantName = assistantName
        _observer = StateObject(wrappedValue: TranscriptObserver(orchestrator: orchestrator))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.98, green: 0.97, blue: 0.95)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(observer.visibleTurns) { turn in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(turn.role == .user ? "You" : assistantName)
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
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(
                                        turn.role == .user
                                            ? Color(red: 0.90, green: 0.96, blue: 0.94)
                                            : Color(red: 0.99, green: 0.96, blue: 0.93)
                                    )
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color(red: 0.92, green: 0.42, blue: 0.27))
        }
        .presentationDetents([.fraction(0.55), .large])
        .presentationDragIndicator(.visible)
    }
}

@MainActor
private func subtitleDisplay(
    state: CallSubtitleState,
    assistantName: String
) -> (speakerTitle: String, subtitle: String, supportingText: String, accent: Color) {
    let liveUser = state.liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    let liveAssistant = state.liveAssistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

    if liveUser.isEmpty == false {
        return (
            speakerTitle: "You",
            subtitle: liveUser,
            supportingText: "Live voice caption. Keep talking or interrupt anytime.",
            accent: Color(red: 0.54, green: 0.76, blue: 1.0)
        )
    }

    if liveAssistant.isEmpty == false {
        return (
            speakerTitle: assistantName,
            subtitle: liveAssistant,
            supportingText: "Streaming reply from your on-device companion.",
            accent: Color(red: 1.0, green: 0.75, blue: 0.54)
        )
    }

    if let lastTurn = state.visibleTurns.last {
        return (
            speakerTitle: lastTurn.role == .user ? "You" : assistantName,
            subtitle: lastTurn.text,
            supportingText: lastTurn.wasInterrupted ? "Reply was interrupted and saved up to that point." : "Most recent turn from this call.",
            accent: lastTurn.role == .user ? Color(red: 0.54, green: 0.76, blue: 1.0) : Color(red: 1.0, green: 0.75, blue: 0.54)
        )
    }

    return (
        speakerTitle: assistantName,
        subtitle: assistantEmptyText(for: state.phase),
        supportingText: "Captions stay on screen here and can be dragged upward for more lines.",
        accent: Color.white
    )
}

@MainActor
private func callStatusText(_ phase: CallPhase) -> String {
    switch phase {
    case .idle:
        return "Call ready."
    case .preparing:
        return "Connecting your offline companion."
    case .listening:
        return "Listening live. Jump in anytime."
    case .thinking:
        return "Thinking on device."
    case .speaking:
        return "Speaking back."
    case .interrupted:
        return "Interrupted. Your turn."
    case .finishing:
        return "Building the session wrap-up locally."
    case let .error(message):
        return message
    }
}

@MainActor
private func assistantEmptyText(for phase: CallPhase) -> String {
    switch phase {
    case .thinking, .preparing:
        return "Your companion is joining the call."
    case .speaking:
        return "Speaking now."
    case .interrupted:
        return "Paused so you can take the floor."
    case .finishing:
        return "Wrapping up this session."
    case .error:
        return "This call needs attention."
    case .idle, .listening:
        return "Ready for the next turn."
    }
}

@MainActor
private func interruptibilityText(for phase: CallPhase, inputMode: CallInputMode) -> String {
    switch phase {
    case .speaking:
        return "Barge-in enabled"
    case .thinking:
        return "Preparing reply"
    case .listening:
        return inputMode == .liveVoice ? "Live listening" : "Text assisted"
    case .interrupted:
        return "Interrupted"
    case .finishing:
        return "Wrapping up"
    case .error:
        return "Attention needed"
    case .idle, .preparing:
        return "Connecting"
    }
}
