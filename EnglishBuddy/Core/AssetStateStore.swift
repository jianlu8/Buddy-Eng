import Foundation

actor AssetStateStore: AssetStateStoreProtocol {
    private let filesystem: AppFilesystem
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(filesystem: AppFilesystem) {
        self.filesystem = filesystem
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadAssetState() async throws -> AssetStateSnapshot {
        try filesystem.prepareDirectories()
        guard FileManager.default.fileExists(atPath: filesystem.assetStateSnapshotURL.path) else {
            return AssetStateSnapshot()
        }

        let data = try Data(contentsOf: filesystem.assetStateSnapshotURL)
        return try decoder.decode(AssetStateSnapshot.self, from: data)
    }

    func saveAssetState(_ snapshot: AssetStateSnapshot) async throws {
        try filesystem.prepareDirectories()
        let data = try encoder.encode(snapshot)
        try data.write(to: filesystem.assetStateSnapshotURL, options: .atomic)
    }

    func recordValidationSnapshot(_ snapshot: ValidationRunSnapshot) async throws {
        var current = try await loadAssetState()
        current.latestValidationSnapshot = snapshot
        current.updatedAt = .now
        try await saveAssetState(current)
    }
}
