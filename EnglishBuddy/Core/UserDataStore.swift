import Foundation

actor UserDataStore: UserDataStoreProtocol {
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

    func loadUserData() async throws -> UserDataSnapshot {
        try filesystem.prepareDirectories()
        guard FileManager.default.fileExists(atPath: filesystem.userDataSnapshotURL.path) else {
            return UserDataSnapshot(memorySnapshot: .default)
        }

        let data = try Data(contentsOf: filesystem.userDataSnapshotURL)
        return try decoder.decode(UserDataSnapshot.self, from: data)
    }

    func saveUserData(_ snapshot: UserDataSnapshot) async throws {
        try filesystem.prepareDirectories()
        let data = try encoder.encode(snapshot)
        try data.write(to: filesystem.userDataSnapshotURL, options: .atomic)
    }

    func deleteAllUserData() async throws {
        try await saveUserData(UserDataSnapshot(memorySnapshot: .default))
    }
}
