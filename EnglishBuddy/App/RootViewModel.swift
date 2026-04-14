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
    @Published var installationBusy = false
    @Published var globalError: String?

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

    func savePersonalization(name: String, goal: String, mode: ConversationMode) async {
        do {
            try await memoryStore.updateLearnerProfile { profile in
                profile.preferredName = name
                profile.learningGoal = goal
                profile.preferredMode = mode
            }
            try await memoryStore.updateCompanionSettings { settings in
                settings.warmupCompleted = true
            }
            await refresh()
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
            await refresh()
        } catch {
            globalError = error.localizedDescription
        }
    }

    func deleteModel() async {
        installationBusy = true
        defer { installationBusy = false }
        do {
            try await modelManager.deleteModel()
            await refresh()
        } catch {
            globalError = error.localizedDescription
        }
    }

    func startCall(_ mode: ConversationMode) async {
        guard canStartCalls else {
            if case let .fatalConfigurationError(message) = bootstrapState {
                globalError = message
            }
            return
        }

        selectedMode = mode
        launchingMode = mode
        callStartupState = .starting("Starting \(mode.title.lowercased()) mode")
        globalError = nil

        let result = await callStartupCoordinator.prepareCall(mode: mode)
        switch result {
        case let .ready(preparedCall):
            orchestrator.beginPreparedCall(preparedCall)
            callStartupState = .idle
            showingCall = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.orchestrator.startOpeningTurnIfNeeded(preparedCall.openingInstruction)
            }
        case let .recoverableFailure(kind, message, suggestedAction):
            orchestrator.failPreparedCall(message: message)
            callStartupState = .recoverableFailure(kind: kind, message: message, suggestedAction: suggestedAction)
        case let .fatalConfigurationFailure(message):
            orchestrator.failPreparedCall(message: message)
            bootstrapState = .fatalConfigurationError(message)
            callStartupState = .idle
        }
    }

    func finishCall() async {
        await orchestrator.endCall()
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
        callStartupState = .idle
    }
}
