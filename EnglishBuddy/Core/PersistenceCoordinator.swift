import Foundation

actor PersistenceCoordinator {
    private let filesystem: AppFilesystem
    private let userDataStore: UserDataStore
    private let modelStateStore: ModelStateStore
    private let assetStateStore: AssetStateStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        filesystem: AppFilesystem,
        userDataStore: UserDataStore,
        modelStateStore: ModelStateStore,
        assetStateStore: AssetStateStore
    ) {
        self.filesystem = filesystem
        self.userDataStore = userDataStore
        self.modelStateStore = modelStateStore
        self.assetStateStore = assetStateStore

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadMemorySnapshot() async throws -> MemorySnapshot {
        try filesystem.prepareDirectories()

        if splitStoreExists {
            return try await materializeMemorySnapshot()
        }

        if FileManager.default.fileExists(atPath: filesystem.snapshotURL.path) {
            let data = try Data(contentsOf: filesystem.snapshotURL)
            let legacySnapshot = try decoder.decode(MemorySnapshot.self, from: data)
            try await bootstrapSplitStores(from: legacySnapshot, installDisposition: .upgrade)
            try persistLegacySnapshot(legacySnapshot)
            return legacySnapshot
        }

        let snapshot = MemorySnapshot.default
        try await bootstrapSplitStores(from: snapshot, installDisposition: .freshInstall)
        try persistLegacySnapshot(snapshot)
        return snapshot
    }

    func persist(memorySnapshot: MemorySnapshot) async throws {
        try filesystem.prepareDirectories()
        try await saveSplitStores(from: memorySnapshot)
        try persistLegacySnapshot(memorySnapshot)
    }

    private var splitStoreExists: Bool {
        FileManager.default.fileExists(atPath: filesystem.userDataSnapshotURL.path)
            && FileManager.default.fileExists(atPath: filesystem.modelStateSnapshotURL.path)
            && FileManager.default.fileExists(atPath: filesystem.assetStateSnapshotURL.path)
    }

    private func materializeMemorySnapshot() async throws -> MemorySnapshot {
        let userData = try await userDataStore.loadUserData()
        let modelState = try await modelStateStore.loadModelState()

        return MemorySnapshot(
            learnerProfile: userData.learnerProfile,
            companionSettings: userData.companionSettings,
            sessions: userData.sessions,
            threadStates: userData.threadStates,
            vocabulary: userData.vocabulary,
            modelInstallationRecords: modelState.modelInstallationRecords,
            modelSelectionState: modelState.modelSelectionState
        )
    }

    private func bootstrapSplitStores(
        from memorySnapshot: MemorySnapshot,
        installDisposition: PersistenceInstallDisposition
    ) async throws {
        let sourceVersion = splitStoreExists ? 2 : 1
        try await saveSplitStores(from: memorySnapshot)

        let receipt = PersistenceMigrationReceipt(
            sourceVersion: sourceVersion,
            targetVersion: 2,
            installDisposition: installDisposition,
            backupFileName: try backupLegacySnapshotIfNeeded(for: installDisposition)
        )
        let data = try encoder.encode(receipt)
        try data.write(to: filesystem.migrationReceiptURL, options: .atomic)
    }

    private func saveSplitStores(from memorySnapshot: MemorySnapshot) async throws {
        try await userDataStore.saveUserData(UserDataSnapshot(memorySnapshot: memorySnapshot))
        try await modelStateStore.saveModelState(ModelStateSnapshot(memorySnapshot: memorySnapshot))

        var assetState = (try? await assetStateStore.loadAssetState()) ?? AssetStateSnapshot()
        assetState.latestValidationSnapshot = latestValidationSnapshot(from: memorySnapshot)
        assetState.updatedAt = .now
        try await assetStateStore.saveAssetState(assetState)
    }

    private func persistLegacySnapshot(_ snapshot: MemorySnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: filesystem.snapshotURL, options: .atomic)
    }

    private func latestValidationSnapshot(from memorySnapshot: MemorySnapshot) -> ValidationRunSnapshot? {
        memorySnapshot.sessions
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
            .compactMap(\.validationSnapshot)
            .first
    }

    private func backupLegacySnapshotIfNeeded(
        for installDisposition: PersistenceInstallDisposition
    ) throws -> String? {
        guard installDisposition == .upgrade else { return nil }
        guard FileManager.default.fileExists(atPath: filesystem.snapshotURL.path) else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let fileName = "memory-snapshot-\(formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")).bak.json"
        let backupURL = filesystem.migrationsDirectoryURL.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: backupURL.path) == false {
            try FileManager.default.copyItem(at: filesystem.snapshotURL, to: backupURL)
        }
        return fileName
    }
}
