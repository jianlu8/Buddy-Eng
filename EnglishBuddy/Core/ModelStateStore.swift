import Foundation

actor ModelStateStore: ModelStateStoreProtocol {
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

    func loadModelState() async throws -> ModelStateSnapshot {
        try filesystem.prepareDirectories()
        guard FileManager.default.fileExists(atPath: filesystem.modelStateSnapshotURL.path) else {
            return ModelStateSnapshot(memorySnapshot: .default)
        }

        let data = try Data(contentsOf: filesystem.modelStateSnapshotURL)
        return try decoder.decode(ModelStateSnapshot.self, from: data)
    }

    func saveModelState(_ snapshot: ModelStateSnapshot) async throws {
        try filesystem.prepareDirectories()
        let data = try encoder.encode(snapshot)
        try data.write(to: filesystem.modelStateSnapshotURL, options: .atomic)
    }
}
