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
        StartupTrace.mark("AppLaunchProvisioner.prepareApp.begin")
        do {
            try await memoryStore.load()
            StartupTrace.mark("AppLaunchProvisioner.prepareApp.memoryLoaded")
            try await modelManager.ensureBundledBaseReady()
            StartupTrace.mark("AppLaunchProvisioner.prepareApp.bundledBaseReady")
            await modelManager.refreshInstallState()
            StartupTrace.mark("AppLaunchProvisioner.prepareApp.installStateRefreshed")

            if case let .unavailable(message) = modelManager.activeModelReadiness {
                let recovered = await modelManager.recoverBundledBaseIfPossible()
                if recovered == false {
                    StartupTrace.mark("AppLaunchProvisioner.prepareApp.fatalUnavailable \(message)")
                    return .fatalConfigurationError(message)
                }
            }

            StartupTrace.mark("AppLaunchProvisioner.prepareApp.ready")
            return .ready
        } catch {
            StartupTrace.mark("AppLaunchProvisioner.prepareApp.error \(error.localizedDescription)")
            return .fatalConfigurationError(error.localizedDescription)
        }
    }
}
