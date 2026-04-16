import Foundation

@MainActor
final class RootViewModel: ObservableObject {
    @Published private(set) var snapshot: MemorySnapshot = .default
    @Published private(set) var bootstrapState: BootstrapReadinessState = .booting("Preparing your offline coach")
    @Published var showingCall = false
    @Published var showingFeedback = false
    @Published var showingHistory = false
    @Published var showingSettings = false
    @Published var showingPersonalizationPrompt = false
    @Published var selectedMode: ConversationMode = .chat
    @Published var launchingMode: ConversationMode = .chat
    @Published var callStartupState: CallStartupState = .idle
    @Published private(set) var latestCallReadinessSnapshot: CallReadinessSnapshot?
    @Published var installationBusy = false
    @Published var globalError: String?
    private var callActivationTask: Task<Void, Never>?

    let memoryStore: FileMemoryStore
    let modelManager: ModelDownloadManager
    let orchestrator: ConversationOrchestrator
    let callStartupCoordinator: CallStartupCoordinator

    init(
        memoryStore: FileMemoryStore,
        modelManager: ModelDownloadManager,
        orchestrator: ConversationOrchestrator,
        callStartupCoordinator: CallStartupCoordinator
    ) {
        self.memoryStore = memoryStore
        self.modelManager = modelManager
        self.orchestrator = orchestrator
        self.callStartupCoordinator = callStartupCoordinator
    }

    var canStartCalls: Bool {
        guard case .ready = bootstrapState else { return false }
        if case .starting = callStartupState {
            return false
        }
        return true
    }

    func bootstrap(using provisioner: AppLaunchProvisioner) async {
        bootstrapState = .booting("Getting your offline coach ready")
        let state = await provisioner.prepareApp()
        bootstrapState = state
        await refresh()
        selectedMode = snapshot.learnerProfile.preferredMode
    }

    func refresh() async {
        snapshot = await memoryStore.fetchSnapshot()
    }

    func updateLearnerProfile(_ mutate: @escaping @Sendable (inout LearnerProfile) -> Void) async throws {
        let previous = snapshot.learnerProfile
        var updated = previous
        mutate(&updated)
        updated.updatedAt = .now
        snapshot.learnerProfile = updated

        do {
            try await memoryStore.updateLearnerProfile(mutate)
        } catch {
            snapshot.learnerProfile = previous
            throw error
        }
    }

    func updateCompanionSettings(_ mutate: @escaping @Sendable (inout CompanionSettings) -> Void) async throws {
        let previous = snapshot.companionSettings
        var updated = previous
        mutate(&updated)
        snapshot.companionSettings = normalizedCompanionSettings(updated)

        do {
            try await memoryStore.updateCompanionSettings(mutate)
        } catch {
            snapshot.companionSettings = previous
            throw error
        }
    }

    func savePersonalization(name: String, goal: String, mode: ConversationMode) async {
        do {
            try await updateLearnerProfile { profile in
                profile.preferredName = name
                profile.learningGoal = goal
                profile.preferredMode = mode
            }
            try await updateCompanionSettings { settings in
                settings.warmupCompleted = true
            }
            showingPersonalizationPrompt = false
        } catch {
            globalError = error.localizedDescription
        }
    }

    func installModel() async {
        installationBusy = true
        defer { installationBusy = false }
        do {
            try await modelManager.downloadModel()
        } catch {
            globalError = error.localizedDescription
        }
    }

    func deleteModel() async {
        installationBusy = true
        defer { installationBusy = false }
        do {
            try await modelManager.deleteModel()
        } catch {
            globalError = error.localizedDescription
        }
    }

    func startCall(
        _ mode: ConversationMode,
        preferredScenarioID: String? = nil,
        continuationAnchor: ConversationSession? = nil
    ) async {
        StartupTrace.mark("RootViewModel.startCall.begin mode=\(mode.rawValue)")
        guard canStartCalls else {
            if case let .fatalConfigurationError(message) = bootstrapState {
                globalError = message
            }
            StartupTrace.mark("RootViewModel.startCall.blocked canStartCalls=false")
            return
        }

        selectedMode = mode
        launchingMode = mode
        callStartupState = .starting("Starting \(mode.title.lowercased()) mode")
        globalError = nil
        callActivationTask?.cancel()

        let result = await callStartupCoordinator.prepareCall(
            mode: mode,
            preferredScenarioID: preferredScenarioID,
            continuationAnchor: continuationAnchor
        )
        StartupTrace.mark("RootViewModel.startCall.prepareCall.completed")
        latestCallReadinessSnapshot = callStartupCoordinator.lastReadinessSnapshot
        switch result {
        case let .ready(preparedCall):
            StartupTrace.mark("RootViewModel.startCall.ready inputMode=\(preparedCall.inputMode.rawValue)")
            orchestrator.beginPreparedCall(preparedCall)
            callStartupState = .idle
            showingCall = true
            StartupTrace.mark("RootViewModel.startCall.showingCall=true")
            callActivationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let failureMessage: String
                do {
                    try await self.orchestrator.activateConversationIfNeeded()
                } catch {
                    failureMessage = error.localizedDescription
                    self.orchestrator.failPreparedCall(message: failureMessage)
                    self.showingCall = false
                    StartupTrace.mark("RootViewModel.startCall.conversationActivation.failed message=\(failureMessage)")
                    self.callStartupState = .recoverableFailure(
                        kind: .inferenceStalled,
                        message: failureMessage,
                        suggestedAction: "The local model could not finish preparing. Return to home and try the call again."
                    )
                    return
                }

                await self.orchestrator.activateLiveAudioIfNeeded()
                await self.orchestrator.startOpeningTurnIfNeeded(preparedCall.openingInstruction)
                guard Task.isCancelled == false else { return }
                guard case let .error(message) = self.orchestrator.phase else { return }
                guard self.orchestrator.visibleTurns.contains(where: { $0.role == .assistant }) == false else { return }

                self.orchestrator.failPreparedCall(message: message)
                self.showingCall = false
                StartupTrace.mark("RootViewModel.startCall.openingTurn.failed message=\(message)")
                self.callStartupState = .recoverableFailure(
                    kind: .inferenceStalled,
                    message: message,
                    suggestedAction: "The opening turn failed before the call fully started. Return to home and try again."
                )
            }
        case let .recoverableFailure(kind, message, suggestedAction):
            StartupTrace.mark("RootViewModel.startCall.recoverableFailure kind=\(String(describing: kind)) message=\(message)")
            callActivationTask?.cancel()
            orchestrator.failPreparedCall(message: message)
            callStartupState = .recoverableFailure(kind: kind, message: message, suggestedAction: suggestedAction)
        case let .fatalConfigurationFailure(message):
            StartupTrace.mark("RootViewModel.startCall.fatalFailure message=\(message)")
            callActivationTask?.cancel()
            orchestrator.failPreparedCall(message: message)
            bootstrapState = .fatalConfigurationError(message)
            callStartupState = .idle
        }
    }

    func finishCall() async {
        callActivationTask?.cancel()
        await orchestrator.endCall()
        showingCall = false
        showingFeedback = orchestrator.latestFeedback != nil
        await refresh()
    }

    func resetMemory() async {
        do {
            try await memoryStore.deleteAllMemory()
            _ = await modelManager.recoverBundledBaseIfPossible()
            await refresh()
        } catch {
            globalError = error.localizedDescription
        }
    }

    func clearCallRecoveryState() {
        callActivationTask?.cancel()
        callStartupState = .idle
        latestCallReadinessSnapshot = nil
    }

    private func normalizedCompanionSettings(_ settings: CompanionSettings) -> CompanionSettings {
        var normalized = settings
        normalized.selectedCharacterID = CharacterCatalog.profile(for: normalized.selectedCharacterID).id
        normalized.selectedSceneID = CharacterCatalog.scene(
            for: normalized.selectedSceneID,
            characterID: normalized.selectedCharacterID
        ).id
        normalized.conversationLanguageID = LanguageCatalog.profile(for: normalized.conversationLanguageID).id
        normalized.explanationLanguageID = LanguageCatalog.profile(for: normalized.explanationLanguageID).id
        normalized.selectedVoiceBundleID = VoiceCatalog.bundle(
            for: normalized.selectedVoiceBundleID,
            characterID: normalized.selectedCharacterID,
            languageID: normalized.conversationLanguageID
        ).id
        normalized.allowChineseHints = normalized.explanationLanguageID != LanguageCatalog.english.id
        normalized.portraitModeEnabled = CharacterCatalog.primaryPortraitAvailable
        return normalized
    }
}
