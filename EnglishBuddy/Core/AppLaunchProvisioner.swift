import Foundation

enum BootstrapReadinessState: Equatable {
    case booting(String)
    case ready
    case fatalConfigurationError(String)
}

@MainActor
final class AppLaunchProvisioner {
    private let memoryStore: FileMemoryStore
    private let modelManager: ModelDownloadManager

    init(memoryStore: FileMemoryStore, modelManager: ModelDownloadManager) {
        self.memoryStore = memoryStore
        self.modelManager = modelManager
    }

    func prepareApp() async -> BootstrapReadinessState {
        do {
            try await memoryStore.load()
            try await modelManager.ensureBundledBaseReady()
            await modelManager.refreshInstallState()

            if case let .unavailable(message) = modelManager.activeModelReadiness {
                let recovered = await modelManager.recoverBundledBaseIfPossible()
                if recovered == false {
                    return .fatalConfigurationError(message)
                }
            }

            return .ready
        } catch {
            return .fatalConfigurationError(error.localizedDescription)
        }
    }
}
