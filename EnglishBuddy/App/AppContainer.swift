import Foundation

@MainActor
final class AppContainer: ObservableObject {
    let rootState: RootViewModel

    let memoryStore: FileMemoryStore
    let feedbackGenerator: FeedbackGenerator
    let promptComposer: PromptComposer
    let speechPipeline: LiveSpeechPipeline
    let inferenceEngine: LiteRTInferenceEngine
    let modelManager: ModelDownloadManager
    let appLaunchProvisioner: AppLaunchProvisioner
    let callStartupCoordinator: CallStartupCoordinator
    let orchestrator: ConversationOrchestrator
    let performanceGovernor: PerformanceGovernor
    private var hasCompletedBootstrap = false
    private var isBootstrapping = false
    private var hasPerformedLaunchAutomation = false
    private var hasQueuedPortraitPrewarm = false
    private var portraitPrewarmTask: Task<Void, Never>?
    private var speechPrewarmTask: Task<Void, Never>?
    private var lastSpeechPrewarmKey: String?

    private init(
        memoryStore: FileMemoryStore,
        feedbackGenerator: FeedbackGenerator,
        promptComposer: PromptComposer,
        speechPipeline: LiveSpeechPipeline,
        inferenceEngine: LiteRTInferenceEngine,
        modelManager: ModelDownloadManager,
        appLaunchProvisioner: AppLaunchProvisioner,
        callStartupCoordinator: CallStartupCoordinator,
        orchestrator: ConversationOrchestrator,
        performanceGovernor: PerformanceGovernor,
        rootState: RootViewModel
    ) {
        self.memoryStore = memoryStore
        self.feedbackGenerator = feedbackGenerator
        self.promptComposer = promptComposer
        self.speechPipeline = speechPipeline
        self.inferenceEngine = inferenceEngine
        self.modelManager = modelManager
        self.appLaunchProvisioner = appLaunchProvisioner
        self.callStartupCoordinator = callStartupCoordinator
        self.orchestrator = orchestrator
        self.performanceGovernor = performanceGovernor
        self.rootState = rootState
    }

    static func bootstrap(baseURL: URL? = nil) -> AppContainer {
        StartupTrace.mark("AppContainer.bootstrap.static.begin")
        let filesystem = AppFilesystem(baseURL: baseURL)
        let memoryStore = FileMemoryStore(filesystem: filesystem)
        let feedbackGenerator = FeedbackGenerator()
        let promptComposer = PromptComposer()
        let speechPipeline = LiveSpeechPipeline(filesystem: filesystem)
        let inferenceEngine = LiteRTInferenceEngine()
        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        let performanceGovernor = PerformanceGovernor()
        let appLaunchProvisioner = AppLaunchProvisioner(memoryStore: memoryStore, modelManager: modelManager)
        let callStartupCoordinator = CallStartupCoordinator(
            inferenceEngine: inferenceEngine,
            speechPipeline: speechPipeline,
            memoryStore: memoryStore,
            promptComposer: promptComposer,
            modelManager: modelManager,
            performanceGovernor: performanceGovernor
        )
        let orchestrator = ConversationOrchestrator(
            inferenceEngine: inferenceEngine,
            speechPipeline: speechPipeline,
            memoryStore: memoryStore,
            promptComposer: promptComposer,
            feedbackGenerator: feedbackGenerator,
            modelManager: modelManager,
            performanceGovernor: performanceGovernor
        )
        let rootState = RootViewModel(
            memoryStore: memoryStore,
            modelManager: modelManager,
            orchestrator: orchestrator,
            callStartupCoordinator: callStartupCoordinator
        )
        let container = AppContainer(
            memoryStore: memoryStore,
            feedbackGenerator: feedbackGenerator,
            promptComposer: promptComposer,
            speechPipeline: speechPipeline,
            inferenceEngine: inferenceEngine,
            modelManager: modelManager,
            appLaunchProvisioner: appLaunchProvisioner,
            callStartupCoordinator: callStartupCoordinator,
            orchestrator: orchestrator,
            performanceGovernor: performanceGovernor,
            rootState: rootState
        )
        StartupTrace.mark("AppContainer.bootstrap.static.ready")
        return container
    }

    func bootstrap(force: Bool = false) async {
        StartupTrace.mark("AppContainer.bootstrap.instance.begin force=\(force)")
        if force {
            hasCompletedBootstrap = false
            hasQueuedPortraitPrewarm = false
            portraitPrewarmTask?.cancel()
            portraitPrewarmTask = nil
            speechPrewarmTask?.cancel()
            speechPrewarmTask = nil
            lastSpeechPrewarmKey = nil
        }
        guard isBootstrapping == false else { return }
        guard force || hasCompletedBootstrap == false else { return }

        isBootstrapping = true
        defer { isBootstrapping = false }

        await rootState.bootstrap(using: appLaunchProvisioner)
        StartupTrace.mark("AppContainer.bootstrap.instance.rootStateReady state=\(String(describing: rootState.bootstrapState))")
        performanceGovernor.apply(settings: rootState.snapshot.companionSettings)
        hasCompletedBootstrap = true
        queuePortraitPrewarmIfNeeded()
        queueSpeechPrewarmForCurrentSelectionIfNeeded()
        await performLaunchAutomationIfNeeded()
        StartupTrace.mark("AppContainer.bootstrap.instance.end")
    }

    func syncPerformanceProfile(using settings: CompanionSettings) {
        performanceGovernor.apply(settings: settings)
    }

    func prewarmSpeechRuntimeIfNeeded(
        characterID: String? = nil,
        languageID: String? = nil,
        voiceBundleID: String? = nil,
        force: Bool = false
    ) {
        let snapshot = rootState.snapshot
        scheduleSpeechPrewarmIfNeeded(
            characterID: characterID ?? snapshot.companionSettings.selectedCharacterID,
            languageID: languageID ?? snapshot.companionSettings.conversationLanguageID,
            voiceBundleID: voiceBundleID ?? snapshot.companionSettings.selectedVoiceBundleID,
            force: force
        )
    }

    private func queuePortraitPrewarmIfNeeded() {
        guard hasQueuedPortraitPrewarm == false else { return }
        guard case .ready = rootState.bootstrapState else { return }

        let bundle = CharacterCatalog.bundle(for: CharacterCatalog.flagship.id)
        guard bundle.renderRuntimeKind == .photoPseudo3D else { return }

        hasQueuedPortraitPrewarm = true
        portraitPrewarmTask = Task { @MainActor in
            await PortraitCharacterRuntime.prewarmIfNeeded(for: bundle)
        }
    }

    private func queueSpeechPrewarmForCurrentSelectionIfNeeded() {
        guard case .ready = rootState.bootstrapState else { return }
        let settings = rootState.snapshot.companionSettings
        scheduleSpeechPrewarmIfNeeded(
            characterID: settings.selectedCharacterID,
            languageID: settings.conversationLanguageID,
            voiceBundleID: settings.selectedVoiceBundleID,
            force: false
        )
    }

    private func scheduleSpeechPrewarmIfNeeded(
        characterID: String,
        languageID: String,
        voiceBundleID: String,
        force: Bool
    ) {
        let character = CharacterCatalog.profile(for: characterID)
        let language = LanguageCatalog.profile(for: languageID)
        let voiceBundle = VoiceCatalog.bundle(
            for: voiceBundleID,
            characterID: character.id,
            languageID: language.id
        )
        guard voiceBundle.prewarmRequired else { return }

        let runtimeStatus = speechPipeline.runtimeStatus(
            conversationLanguage: language,
            voiceBundle: voiceBundle
        )
        guard runtimeStatus.tts.activeRuntimeID == "kokoro-tts" || runtimeStatus.tts.activeRuntimeID == "piper-tts" else {
            return
        }

        let prewarmKey = [
            character.id,
            language.id,
            voiceBundle.id,
            runtimeStatus.tts.activeRuntimeID
        ].joined(separator: "|")
        guard force || lastSpeechPrewarmKey != prewarmKey else { return }

        lastSpeechPrewarmKey = prewarmKey
        speechPrewarmTask?.cancel()
        speechPrewarmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            StartupTrace.mark("AppContainer.scheduleSpeechPrewarmIfNeeded.begin voice=\(voiceBundle.id)")
            do {
                try await self.speechPipeline.prepareTTS(voiceBundle: voiceBundle)
                StartupTrace.mark("AppContainer.scheduleSpeechPrewarmIfNeeded.ready voice=\(voiceBundle.id)")
            } catch {
                StartupTrace.mark("AppContainer.scheduleSpeechPrewarmIfNeeded.failed voice=\(voiceBundle.id) message=\(error.localizedDescription)")
            }
        }
    }

    private func performLaunchAutomationIfNeeded() async {
        guard hasPerformedLaunchAutomation == false else { return }
        guard case .ready = rootState.bootstrapState else { return }
        StartupTrace.mark("AppContainer.performLaunchAutomationIfNeeded.ready")

        let arguments = ProcessInfo.processInfo.arguments
        let mode: ConversationMode?
        if arguments.contains("--autostart-chat-call") {
            mode = .chat
        } else if arguments.contains("--autostart-tutor-call") {
            mode = .tutor
        } else {
            mode = nil
        }

        guard let mode else {
            StartupTrace.mark("AppContainer.performLaunchAutomationIfNeeded.noMode")
            return
        }
        hasPerformedLaunchAutomation = true
        StartupTrace.mark("AppContainer.performLaunchAutomationIfNeeded.startCall mode=\(mode.rawValue)")
        await rootState.startCall(mode)

        guard rootState.showingCall else {
            StartupTrace.mark("AppContainer.performLaunchAutomationIfNeeded.showingCall=false")
            return
        }
        guard let message = launchAutomationMessage(from: arguments) else {
            StartupTrace.mark("AppContainer.performLaunchAutomationIfNeeded.noAutoMessage")
            return
        }
        StartupTrace.mark("AppContainer.performLaunchAutomationIfNeeded.autoSendMessage")
        await orchestrator.sendTextFallback(message)
    }

    private func launchAutomationMessage(from arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: "--auto-send-message") else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else { return nil }
        let message = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }
}
