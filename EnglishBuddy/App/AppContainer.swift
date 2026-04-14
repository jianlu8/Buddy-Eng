import Combine
import Foundation

@MainActor
final class AppContainer: ObservableObject {
    @Published var rootState: RootViewModel

    let memoryStore: FileMemoryStore
    let feedbackGenerator: FeedbackGenerator
    let promptComposer: PromptComposer
    let speechPipeline: LiveSpeechPipeline
    let inferenceEngine: LiteRTInferenceEngine
    let modelManager: ModelDownloadManager
    let appLaunchProvisioner: AppLaunchProvisioner
    let callStartupCoordinator: CallStartupCoordinator
    let orchestrator: ConversationOrchestrator
    private var childObservationCancellables: Set<AnyCancellable> = []
    private var hasCompletedBootstrap = false
    private var isBootstrapping = false
    private var hasPerformedLaunchAutomation = false

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
        self.rootState = rootState
        bindChildState()
    }

    static func bootstrap(baseURL: URL? = nil) -> AppContainer {
        let filesystem = AppFilesystem(baseURL: baseURL)
        let memoryStore = FileMemoryStore(filesystem: filesystem)
        let feedbackGenerator = FeedbackGenerator()
        let promptComposer = PromptComposer()
        let speechPipeline = LiveSpeechPipeline()
        let inferenceEngine = LiteRTInferenceEngine()
        let modelManager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        let appLaunchProvisioner = AppLaunchProvisioner(memoryStore: memoryStore, modelManager: modelManager)
        let callStartupCoordinator = CallStartupCoordinator(
            inferenceEngine: inferenceEngine,
            speechPipeline: speechPipeline,
            memoryStore: memoryStore,
            promptComposer: promptComposer,
            modelManager: modelManager
        )
        let orchestrator = ConversationOrchestrator(
            inferenceEngine: inferenceEngine,
            speechPipeline: speechPipeline,
            memoryStore: memoryStore,
            promptComposer: promptComposer,
            feedbackGenerator: feedbackGenerator,
            modelManager: modelManager
        )
        let rootState = RootViewModel(
            memoryStore: memoryStore,
            modelManager: modelManager,
            orchestrator: orchestrator,
            callStartupCoordinator: callStartupCoordinator
        )
        return AppContainer(
            memoryStore: memoryStore,
            feedbackGenerator: feedbackGenerator,
            promptComposer: promptComposer,
            speechPipeline: speechPipeline,
            inferenceEngine: inferenceEngine,
            modelManager: modelManager,
            appLaunchProvisioner: appLaunchProvisioner,
            callStartupCoordinator: callStartupCoordinator,
            orchestrator: orchestrator,
            rootState: rootState
        )
    }

    func bootstrap(force: Bool = false) async {
        if force {
            hasCompletedBootstrap = false
        }
        guard isBootstrapping == false else { return }
        guard force || hasCompletedBootstrap == false else { return }

        isBootstrapping = true
        defer { isBootstrapping = false }

        await rootState.bootstrap(using: appLaunchProvisioner)
        hasCompletedBootstrap = true
        await performLaunchAutomationIfNeeded()
    }

    private func bindChildState() {
        let childPublishers: [ObservableObjectPublisher] = [
            rootState.objectWillChange,
            modelManager.objectWillChange,
            orchestrator.objectWillChange
        ]

        for publisher in childPublishers {
            publisher
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &childObservationCancellables)
        }
    }

    private func performLaunchAutomationIfNeeded() async {
        guard hasPerformedLaunchAutomation == false else { return }
        guard case .ready = rootState.bootstrapState else { return }

        let arguments = ProcessInfo.processInfo.arguments
        let mode: ConversationMode?
        if arguments.contains("--autostart-chat-call") {
            mode = .chat
        } else if arguments.contains("--autostart-tutor-call") {
            mode = .tutor
        } else {
            mode = nil
        }

        guard let mode else { return }
        hasPerformedLaunchAutomation = true
        await rootState.startCall(mode)

        guard rootState.showingCall else { return }
        guard let message = launchAutomationMessage(from: arguments) else { return }
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
