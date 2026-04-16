import Combine
import CryptoKit
import Foundation

@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {
    @Published private(set) var catalog: ModelCatalog
    @Published private(set) var installationRecords: [String: ModelInstallationRecord]
    @Published private(set) var selectionState: ModelSelectionState

    private let filesystem: AppFilesystem
    private let memoryStore: FileMemoryStore

    init(filesystem: AppFilesystem, memoryStore: FileMemoryStore) {
        self.filesystem = filesystem
        self.memoryStore = memoryStore
        catalog = .current
        installationRecords = Dictionary(uniqueKeysWithValues: ModelCatalog.current.defaultRecords().map { ($0.modelID, $0) })
        selectionState = ModelCatalog.current.defaultSelectionState
        super.init()
    }

    var selectedModel: ModelDescriptor {
        catalog.descriptor(for: selectionState.selectedModelID) ?? catalog.defaultDescriptor
    }

    var selectedRecord: ModelInstallationRecord {
        record(for: selectedModel.id)
    }

    var activeModelReadiness: ActiveModelReadiness {
        if selectedRecord.isReadyForInference {
            return .ready
        }
        if let reason = selectedRecord.failureReason, reason.isEmpty == false {
            return .unavailable(reason)
        }
        if selectedModel.isBundledBase {
            return .unavailable("\(selectedModel.displayName) is unavailable. Reinstall a build that embeds the bundled base model or stage the bundled base asset into Application Support.")
        }
        return .unavailable("\(selectedModel.displayName) is not available for offline inference yet.")
    }

    var modelURL: URL {
        resolvedModelURL(for: selectedModel) ?? filesystem.downloadedModelURL(for: selectedModel)
    }

    var cachedIntegrityState: Bool {
        selectedRecord.integrityCheckPassed
    }

    func record(for modelID: String) -> ModelInstallationRecord {
        installationRecords[modelID] ?? catalog.defaultRecord(for: modelID)
    }

    func resolvedModelURL(for descriptor: ModelDescriptor) -> URL? {
        if let resolvedURL = record(for: descriptor.id).resolvedURL,
           FileManager.default.fileExists(atPath: resolvedURL.path) {
            return resolvedURL
        }

        if let embeddedURL = embeddedModelURL(for: descriptor) {
            return embeddedURL
        }

        if let localURL = localModelURL(for: descriptor) {
            return localURL
        }

        return nil
    }

    func refreshInstallState() async {
        let snapshot = await memoryStore.fetchSnapshot()
        catalog = .current
        installationRecords = Dictionary(
            uniqueKeysWithValues: catalog.mergedRecords(with: snapshot.modelInstallationRecords).map { ($0.modelID, $0) }
        )
        selectionState = snapshot.modelSelectionState
        normalizeSelection()

        do {
            try filesystem.prepareDirectories()
        } catch {
            applyFailure(error, to: selectedModel.id)
            try? await persistState()
            return
        }

        for descriptor in catalog.descriptors {
            do {
                if let embeddedURL = embeddedModelURL(for: descriptor) {
                    try validateInstalledModel(
                        descriptor: descriptor,
                        at: embeddedURL,
                        recalculateChecksum: false,
                        source: .bundledApp
                    )
                } else if let localURL = localModelURL(for: descriptor) {
                    try validateInstalledModel(
                        descriptor: descriptor,
                        at: localURL,
                        recalculateChecksum: record(for: descriptor.id).integrityCheckPassed == false,
                        source: .downloaded
                    )
                } else if record(for: descriptor.id).status != .downloading {
                    installationRecords[descriptor.id] = resetRecordForMissingArtifact(
                        descriptor: descriptor,
                        from: record(for: descriptor.id)
                    )
                }
            } catch {
                applyFailure(error, to: descriptor.id)
            }
        }

        normalizeSelection()
        try? await persistState()
    }

    func ensureBundledBaseReady() async throws {
        let descriptor = catalog.defaultDescriptor
        selectionState.defaultModelID = descriptor.id
        selectionState.selectedModelID = descriptor.id
        try filesystem.prepareDirectories()

        guard let bundledBaseURL = bundledBaseURL(for: descriptor) else {
            throw ModelManagerError.missingBundledModel(descriptor.displayName)
        }

        try validateInstalledModel(
            descriptor: descriptor,
            at: bundledBaseURL,
            recalculateChecksum: bundledBaseURL.path != embeddedModelURL(for: descriptor)?.path,
            source: bundledBaseURL.path == embeddedModelURL(for: descriptor)?.path ? .bundledApp : .downloaded
        )
        normalizeSelection()
        try await persistState()
    }

    func recoverBundledBaseIfPossible() async -> Bool {
        do {
            try await ensureBundledBaseReady()
            await refreshInstallState()
            return selectedRecord.isReadyForInference
        } catch {
            applyFailure(error, to: catalog.defaultDescriptor.id)
            try? await persistState()
            return false
        }
    }

    func selectModel(_ modelID: String) async throws {
        guard let descriptor = catalog.descriptor(for: modelID), descriptor.isSelectable else {
            throw ModelManagerError.unknownModel(modelID)
        }

        guard record(for: modelID).isReadyForInference else {
            throw ModelManagerError.modelNotInstalled(descriptor.displayName)
        }

        selectionState.selectedModelID = modelID
        try await persistState()
    }

    func installModel(_ modelID: String) async throws {
        guard let descriptor = catalog.descriptor(for: modelID) else {
            throw ModelManagerError.unknownModel(modelID)
        }

        if descriptor.isBundledBase {
            guard let embeddedURL = embeddedModelURL(for: descriptor) else {
                throw ModelManagerError.missingBundledModel(descriptor.displayName)
            }
            try validateInstalledModel(
                descriptor: descriptor,
                at: embeddedURL,
                recalculateChecksum: false,
                source: .bundledApp
            )
            selectionState.selectedModelID = descriptor.id
            try await persistState()
            return
        }

        guard let downloadURL = descriptor.downloadURL else {
            throw ModelManagerError.downloadUnavailable(descriptor.displayName)
        }

        try filesystem.prepareDirectories(for: descriptor)
        try ensureEnoughDiskSpace(for: descriptor)

        var installRecord = record(for: descriptor.id)
        installRecord.status = .downloading
        installRecord.progress = 0.05
        installRecord.failureReason = nil
        installRecord.integrityCheckPassed = false
        installRecord.artifactSource = nil
        installRecord.resolvedURL = nil
        installationRecords[descriptor.id] = installRecord
        try await persistState()

        let temporaryURL: URL
        do {
            let result = try await URLSession.shared.download(from: downloadURL)
            temporaryURL = result.0
        } catch {
            applyFailure(error, to: descriptor.id)
            try? await persistState()
            throw error
        }

        installRecord = record(for: descriptor.id)
        installRecord.progress = 0.8
        installationRecords[descriptor.id] = installRecord

        let stagedURL = filesystem.stagedDownloadURL(for: descriptor)
        if FileManager.default.fileExists(atPath: stagedURL.path) {
            try FileManager.default.removeItem(at: stagedURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: stagedURL)

        do {
            let fileSize = try fileSizeForItem(at: stagedURL)
            guard fileSize == descriptor.expectedFileSizeBytes else {
                throw ModelManagerError.sizeMismatch(expected: descriptor.expectedFileSizeBytes, actual: fileSize)
            }

            let checksum = try Self.calculateSHA256(for: stagedURL)
            if let expectedChecksum = descriptor.checksum, expectedChecksum != checksum {
                throw ModelManagerError.checksumMismatch(expected: expectedChecksum, actual: checksum)
            }

            installRecord = record(for: descriptor.id)
            installRecord.progress = 0.97
            installationRecords[descriptor.id] = installRecord

            let finalURL = filesystem.downloadedModelURL(for: descriptor)
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: stagedURL, to: finalURL)

            installRecord = record(for: descriptor.id)
            installRecord.fileSizeBytes = fileSize
            installRecord.checksum = checksum
            installRecord.lastValidatedAt = .now
            installRecord.lastUsedAt = nil
            installRecord.progress = 1
            installRecord.status = .installed
            installRecord.integrityCheckPassed = true
            installRecord.artifactSource = .downloaded
            installRecord.resolvedURL = finalURL
            installRecord.failureReason = nil
            installationRecords[descriptor.id] = installRecord
            try await persistState()
        } catch {
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try? FileManager.default.removeItem(at: stagedURL)
            }
            applyFailure(error, to: descriptor.id)
            try? await persistState()
            throw error
        }
    }

    func downloadModel() async throws {
        try await installModel(selectedModel.id)
    }

    func markModelUsed() async {
        var record = selectedRecord
        record.lastUsedAt = .now
        installationRecords[selectedModel.id] = record
        if record.isReadyForInference {
            try? await persistState()
        }
    }

    func deleteModel(_ modelID: String) async throws {
        guard let descriptor = catalog.descriptor(for: modelID) else {
            throw ModelManagerError.unknownModel(modelID)
        }

        if descriptor.isDeletable == false {
            if let embeddedURL = embeddedModelURL(for: descriptor) {
                try validateInstalledModel(
                    descriptor: descriptor,
                    at: embeddedURL,
                    recalculateChecksum: false,
                    source: .bundledApp
                )
            } else {
                installationRecords[descriptor.id] = resetRecordForMissingArtifact(
                    descriptor: descriptor,
                    from: record(for: descriptor.id)
                )
            }
            selectionState.selectedModelID = selectionState.defaultModelID
            try await persistState()
            return
        }

        if let localURL = localModelURL(for: descriptor) {
            try FileManager.default.removeItem(at: localURL)
        }

        installationRecords[descriptor.id] = resetRecordForMissingArtifact(
            descriptor: descriptor,
            from: record(for: descriptor.id)
        )

        if selectionState.selectedModelID == modelID {
            selectionState.selectedModelID = selectionState.defaultModelID
        }
        normalizeSelection()
        try await persistState()
    }

    func deleteModel() async throws {
        try await deleteModel(selectedModel.id)
    }

    func repairCorruptionIfNeeded(for modelID: String? = nil) async {
        let targetID = modelID ?? selectedModel.id
        guard let descriptor = catalog.descriptor(for: targetID) else { return }
        let candidateURL = embeddedModelURL(for: descriptor) ?? localModelURL(for: descriptor)
        guard let candidateURL else { return }

        do {
            try validateInstalledModel(
                descriptor: descriptor,
                at: candidateURL,
                recalculateChecksum: record(for: descriptor.id).artifactSource != .bundledApp,
                source: candidateURL == embeddedModelURL(for: descriptor) ? .bundledApp : .downloaded
            )
            normalizeSelection()
            try await persistState()
        } catch {
            applyFailure(error, to: descriptor.id)
            try? await persistState()
        }
    }

    func repairCorruptionIfNeeded() async {
        await repairCorruptionIfNeeded(for: selectedModel.id)
    }

    static func calculateSHA256(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 1024 * 1024)
            guard let data, data.isEmpty == false else { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func persistState() async throws {
        try await memoryStore.updateModelCatalogState(
            records: Array(installationRecords.values),
            selectionState: selectionState
        )
    }

    private func normalizeSelection() {
        if catalog.descriptor(for: selectionState.defaultModelID) == nil {
            selectionState.defaultModelID = catalog.defaultSelectionState.defaultModelID
        }

        if catalog.descriptor(for: selectionState.selectedModelID) == nil {
            selectionState.selectedModelID = selectionState.defaultModelID
        }

        guard record(for: selectionState.selectedModelID).isReadyForInference == false else { return }
        let defaultID = selectionState.defaultModelID
        if record(for: defaultID).isReadyForInference {
            selectionState.selectedModelID = defaultID
        }
    }

    private func localModelURL(for descriptor: ModelDescriptor) -> URL? {
        let localURL = filesystem.downloadedModelURL(for: descriptor)
        guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
        return localURL
    }

    private func embeddedModelURL(for descriptor: ModelDescriptor) -> URL? {
        guard let embeddedURL = filesystem.embeddedModelURL(for: descriptor) else { return nil }
        guard FileManager.default.fileExists(atPath: embeddedURL.path) else { return nil }
        return embeddedURL
    }

    private func bundledBaseURL(for descriptor: ModelDescriptor) -> URL? {
        if let embeddedURL = embeddedModelURL(for: descriptor) {
            return embeddedURL
        }

        return localModelURL(for: descriptor)
    }

    private func validateInstalledModel(
        descriptor: ModelDescriptor,
        at url: URL,
        recalculateChecksum: Bool,
        source: ModelArtifactSource
    ) throws {
        var installRecord = record(for: descriptor.id)
        let currentSize = try fileSizeForItem(at: url)
        installRecord.fileSizeBytes = currentSize

        if source == .bundledApp {
            let metadata = try loadEmbeddedModelMetadata(for: descriptor)
            guard currentSize == metadata.expectedFileSizeBytes else {
                throw ModelManagerError.sizeMismatch(expected: metadata.expectedFileSizeBytes, actual: currentSize)
            }
            installRecord.checksum = metadata.checksum
        } else {
            let trustedLocalMetadata = try loadTrustedLocalModelMetadataIfAvailable(
                for: descriptor,
                at: url
            )
            let expectedSize = trustedLocalMetadata?.expectedFileSizeBytes ?? descriptor.expectedFileSizeBytes
            guard currentSize == expectedSize else {
                throw ModelManagerError.sizeMismatch(expected: expectedSize, actual: currentSize)
            }

            if let trustedLocalMetadata {
                installRecord.checksum = trustedLocalMetadata.checksum ?? descriptor.checksum
            } else if recalculateChecksum || installRecord.checksum == nil {
                let checksum = try Self.calculateSHA256(for: url)
                if let expectedChecksum = descriptor.checksum, expectedChecksum != checksum {
                    throw ModelManagerError.checksumMismatch(expected: expectedChecksum, actual: checksum)
                }
                installRecord.checksum = checksum
            }
        }

        installRecord.lastValidatedAt = .now
        installRecord.integrityCheckPassed = true
        installRecord.status = .installed
        installRecord.failureReason = nil
        installRecord.progress = 1
        installRecord.artifactSource = source
        installRecord.resolvedURL = url
        installationRecords[descriptor.id] = installRecord
    }

    private func loadTrustedLocalModelMetadataIfAvailable(
        for descriptor: ModelDescriptor,
        at url: URL
    ) throws -> EmbeddedModelMetadata? {
        guard descriptor.isBundledBase else { return nil }
        guard url == localModelURL(for: descriptor) else { return nil }

        let metadataURL = filesystem.localModelMetadataURL(for: descriptor)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }

        let data = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(EmbeddedModelMetadata.self, from: data)
        if let modelID = metadata.modelID, modelID != descriptor.id {
            throw ModelManagerError.embeddedMetadataMismatch(expected: descriptor.id, actual: modelID)
        }
        return metadata
    }

    private func loadEmbeddedModelMetadata(for descriptor: ModelDescriptor) throws -> EmbeddedModelMetadata {
        guard let metadataURL = filesystem.embeddedModelMetadataURL(for: descriptor) else {
            return EmbeddedModelMetadata(
                modelID: descriptor.id,
                fileName: descriptor.fileName,
                version: descriptor.version,
                expectedFileSizeBytes: descriptor.expectedFileSizeBytes,
                checksum: descriptor.checksum
            )
        }

        let data = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(EmbeddedModelMetadata.self, from: data)
        if let modelID = metadata.modelID, modelID != descriptor.id {
            throw ModelManagerError.embeddedMetadataMismatch(expected: descriptor.id, actual: modelID)
        }
        return metadata
    }

    private func ensureEnoughDiskSpace(for descriptor: ModelDescriptor) throws {
        let requiredBytes = descriptor.expectedFileSizeBytes + 512 * 1_024 * 1_024
        let values = try filesystem.modelsDirectoryURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let fallback = try FileManager.default.attributesOfFileSystem(forPath: filesystem.modelsDirectoryURL.path)[.systemFreeSize] as? NSNumber
        let importantCapacity = values.volumeAvailableCapacityForImportantUsage
        let standardCapacity = values.volumeAvailableCapacity
        let available: Int64
        if let importantCapacity {
            available = Int64(importantCapacity)
        } else if let standardCapacity {
            available = Int64(standardCapacity)
        } else if let fallback {
            available = fallback.int64Value
        } else {
            available = 0
        }
        guard available >= requiredBytes else {
            throw ModelManagerError.insufficientDiskSpace(required: requiredBytes, available: available)
        }
    }

    private func fileSizeForItem(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func resetRecordForMissingArtifact(
        descriptor: ModelDescriptor,
        from existingRecord: ModelInstallationRecord
    ) -> ModelInstallationRecord {
        var record = existingRecord
        record.status = .notInstalled
        record.progress = 0
        record.fileSizeBytes = nil
        record.checksum = nil
        record.integrityCheckPassed = false
        record.resolvedURL = nil
        record.lastValidatedAt = nil
        record.lastUsedAt = nil
        record.failureReason = nil
        record.artifactSource = nil
        if descriptor.isBundledBase == false {
            return record
        }
        return record
    }

    private func applyFailure(_ error: Error, to modelID: String) {
        var installRecord = record(for: modelID)
        installRecord.status = error is ModelManagerError ? .corrupted : .failed
        installRecord.failureReason = error.localizedDescription
        installRecord.integrityCheckPassed = false
        installRecord.resolvedURL = nil
        installRecord.progress = 0
        installationRecords[modelID] = installRecord
    }
}

private struct EmbeddedModelMetadata: Codable, Equatable {
    var modelID: String?
    var fileName: String
    var version: String
    var expectedFileSizeBytes: Int64
    var checksum: String?
}

private enum ModelManagerError: LocalizedError {
    case unknownModel(String)
    case modelNotInstalled(String)
    case missingBundledModel(String)
    case downloadUnavailable(String)
    case embeddedMetadataMismatch(expected: String, actual: String)
    case insufficientDiskSpace(required: Int64, available: Int64)
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case let .unknownModel(modelID):
            return "Unknown model identifier: \(modelID)."
        case let .modelNotInstalled(displayName):
            return "\(displayName) is not installed and ready for offline inference yet."
        case let .missingBundledModel(displayName):
            return "\(displayName) is not bundled into this app build. Reinstall the app with the bundled base model included."
        case let .downloadUnavailable(displayName):
            return "\(displayName) is reserved for future downloads, but no download URL is available in this build."
        case let .embeddedMetadataMismatch(expected, actual):
            return "Embedded model metadata mismatch. Expected \(expected), got \(actual)."
        case let .insufficientDiskSpace(required, available):
            let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Not enough free space for the model download. Required: \(requiredText). Available: \(availableText)."
        case let .sizeMismatch(expected, actual):
            let expectedText = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            let actualText = ByteCountFormatter.string(fromByteCount: actual, countStyle: .file)
            return "Model size mismatch. Expected \(expectedText), got \(actualText)."
        case let .checksumMismatch(expected, actual):
            return "Model checksum mismatch. Expected \(expected), got \(actual)."
        }
    }
}
