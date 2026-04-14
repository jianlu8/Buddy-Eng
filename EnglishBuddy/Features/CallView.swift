import SwiftUI

struct CallView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var typedFallback = ""
    @State private var showingTextComposer = false
    @State private var subtitleOverlay = SubtitleOverlayState()

    var body: some View {
        let orchestrator = container.orchestrator
        let session = orchestrator.activeSession
        let character = CharacterCatalog.profile(for: session?.characterID ?? container.rootState.snapshot.companionSettings.selectedCharacterID)
        let scene = CharacterCatalog.scene(
            for: session?.sceneID ?? container.rootState.snapshot.companionSettings.selectedSceneID,
            characterID: character.id
        )
        let scenario = session?.scenarioID.flatMap { ScenarioCatalog.preset(for: $0, mode: session?.mode ?? container.rootState.launchingMode) }

        return GeometryReader { proxy in
            ZStack {
                callBackground(for: scene)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header(character: character, scene: scene, scenario: scenario, orchestrator: orchestrator)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                    Spacer(minLength: 0)

                    stage(character: character, scene: scene, orchestrator: orchestrator, size: proxy.size)

                    Spacer(minLength: 0)
                }

                subtitleOverlayView(
                    orchestrator: orchestrator,
                    character: character,
                    size: proxy.size
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                bottomControls(orchestrator: orchestrator)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18 + proxy.safeAreaInsets.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .foregroundStyle(.white)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showingTextComposer) {
            TextFallbackComposer(
                text: $typedFallback,
                sendAction: sendTypedFallback
            )
        }
        .sheet(isPresented: Binding(
            get: { subtitleOverlay.mode == .fullTranscript },
            set: { newValue in
                if newValue == false {
                    subtitleOverlay.mode = .expanded
                }
            }
        )) {
            TranscriptSheet(
                turns: container.orchestrator.visibleTurns,
                assistantName: character.displayName
            )
        }
        .onAppear {
            syncSubtitleState(with: orchestrator)
        }
        .onChange(of: orchestrator.liveUserTranscript) { _ in
            syncSubtitleState(with: orchestrator)
        }
        .onChange(of: orchestrator.liveAssistantTranscript) { _ in
            syncSubtitleState(with: orchestrator)
        }
        .onChange(of: orchestrator.subtitleSpeaker) { _ in
            syncSubtitleState(with: orchestrator)
        }
        .onChange(of: orchestrator.phase) { _ in
            syncSubtitleState(with: orchestrator)
        }
    }

    private func header(
        character: CharacterProfile,
        scene: CharacterScene,
        scenario: ScenarioPreset?,
        orchestrator: ConversationOrchestrator
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(character.displayName)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text(callStatusText(orchestrator.phase))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                StatusPill(text: orchestrator.activeMode?.title ?? container.rootState.launchingMode.title)
            }

            HStack(spacing: 8) {
                StatusPill(text: scene.title)
                if let scenario {
                    StatusPill(text: scenario.title)
                }
                StatusPill(text: interruptibilityText(for: orchestrator.phase, inputMode: orchestrator.inputMode))
            }
        }
    }

    private func stage(
        character: CharacterProfile,
        scene: CharacterScene,
        orchestrator: ConversationOrchestrator,
        size: CGSize
    ) -> some View {
        MiraAvatarView(
            state: orchestrator.avatarState,
            audioLevel: orchestrator.audioLevel,
            emphasis: .hero,
            characterID: character.id,
            sceneID: scene.id
        )
        .frame(width: min(size.width - 24, 410), height: size.height * 0.66)
        .shadow(color: .black.opacity(0.25), radius: 40, y: 24)
        .padding(.bottom, subtitleOverlay.mode == .collapsed ? 132 : 210)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: subtitleOverlay.mode)
    }

    private func subtitleOverlayView(
        orchestrator: ConversationOrchestrator,
        character: CharacterProfile,
        size: CGSize
    ) -> some View {
        let config = overlayConfiguration(for: size.height)
        let display = subtitleDisplay(orchestrator: orchestrator, assistantName: character.displayName)

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
                        Text(display.subtitle)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(config.lineLimit)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        subtitleOverlay.mode = .fullTranscript
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }

                if display.supportingText.isEmpty == false {
                    Text(display.supportingText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: config.minHeight, maxHeight: config.maxHeight, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.42))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 104)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { value in
                        handleOverlayDrag(value.translation.height)
                    }
            )
        }
    }

    private func bottomControls(orchestrator: ConversationOrchestrator) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    subtitleOverlay.mode = subtitleOverlay.mode == .collapsed ? .expanded : .collapsed
                }
            } label: {
                Label(subtitleOverlay.mode == .collapsed ? "Expand Captions" : "Collapse Captions", systemImage: subtitleOverlay.mode == .collapsed ? "captions.bubble" : "captions.bubble.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Button {
                showingTextComposer = true
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await container.rootState.finishCall()
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

    private func callBackground(for scene: CharacterScene) -> some View {
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

    private func subtitleDisplay(
        orchestrator: ConversationOrchestrator,
        assistantName: String
    ) -> (speakerTitle: String, subtitle: String, supportingText: String, accent: Color) {
        let liveUser = orchestrator.liveUserTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveAssistant = orchestrator.liveAssistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

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

        if let lastTurn = orchestrator.visibleTurns.last {
            return (
                speakerTitle: lastTurn.role == .user ? "You" : assistantName,
                subtitle: lastTurn.text,
                supportingText: lastTurn.wasInterrupted ? "Reply was interrupted and saved up to that point." : "Most recent turn from this call.",
                accent: lastTurn.role == .user ? Color(red: 0.54, green: 0.76, blue: 1.0) : Color(red: 1.0, green: 0.75, blue: 0.54)
            )
        }

        return (
            speakerTitle: assistantName,
            subtitle: assistantEmptyText(for: orchestrator.phase),
            supportingText: "Captions stay on screen here and can be dragged upward for more lines.",
            accent: Color.white
        )
    }

    private func overlayConfiguration(for height: CGFloat) -> (minHeight: CGFloat, maxHeight: CGFloat, lineLimit: Int?) {
        switch subtitleOverlay.mode {
        case .collapsed:
            return (minHeight: max(146, height * 0.18), maxHeight: max(164, height * 0.22), lineLimit: 4)
        case .expanded:
            return (minHeight: max(240, height * 0.32), maxHeight: max(320, height * 0.45), lineLimit: 12)
        case .fullTranscript:
            return (minHeight: max(240, height * 0.32), maxHeight: max(320, height * 0.45), lineLimit: 12)
        }
    }

    private func handleOverlayDrag(_ translation: CGFloat) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            if translation < -50 {
                subtitleOverlay.mode = .expanded
            } else if translation > 50 {
                subtitleOverlay.mode = .collapsed
            }
        }
    }

    private func syncSubtitleState(with orchestrator: ConversationOrchestrator) {
        let display = subtitleDisplay(
            orchestrator: orchestrator,
            assistantName: CharacterCatalog.profile(for: orchestrator.activeSession?.characterID ?? container.rootState.snapshot.companionSettings.selectedCharacterID).displayName
        )
        subtitleOverlay.primarySpeaker = orchestrator.subtitleSpeaker
        subtitleOverlay.liveText = display.subtitle
    }

    private func sendTypedFallback() {
        let text = typedFallback
        typedFallback = ""
        showingTextComposer = false
        Task {
            await container.orchestrator.sendTextFallback(text)
        }
    }

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
}

private struct StatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.12)))
    }
}

private struct TranscriptSheet: View {
    let turns: [ConversationTurn]
    let assistantName: String

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(turns) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(turn.role == .user ? "You" : assistantName)
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(turn.text)
                                .font(.system(.body, design: .rounded))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(turn.role == .user ? Color.blue.opacity(0.08) : Color.orange.opacity(0.10))
                        )
                    }
                }
                .padding(20)
            }
            .background(Color(red: 0.98, green: 0.97, blue: 0.95))
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct TextFallbackComposer: View {
    @Binding var text: String
    let sendAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Voice stays primary, but you can steer the call from the keyboard at any time.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("Type your message", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Type Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send", action: sendAction)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.fraction(0.34)])
    }
}
