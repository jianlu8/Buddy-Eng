import XCTest
@testable import EnglishBuddyCore

@MainActor
final class AppLaunchProvisionerTests: XCTestCase {
    func testPrepareAppMarksBundledBaseReadyOnFirstLaunch() async throws {
        let (filesystem, memoryStore) = try makeEmbeddedFixture()
        let manager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        let provisioner = AppLaunchProvisioner(memoryStore: memoryStore, modelManager: manager)

        let state = await provisioner.prepareApp()

        XCTAssertEqual(state, .ready)
        XCTAssertEqual(manager.selectionState.selectedModelID, ModelCatalog.current.defaultDescriptor.id)
        XCTAssertEqual(manager.selectedRecord.status, .installed)
        XCTAssertTrue(manager.selectedRecord.integrityCheckPassed)
        XCTAssertEqual(manager.activeModelReadiness, .ready)
    }

    func testPrepareAppFailsWhenBundledBaseIsMissing() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filesystem = AppFilesystem(baseURL: baseURL)
        let memoryStore = FileMemoryStore(filesystem: filesystem)
        let manager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        let provisioner = AppLaunchProvisioner(memoryStore: memoryStore, modelManager: manager)

        let state = await provisioner.prepareApp()

        guard case let .fatalConfigurationError(message) = state else {
            return XCTFail("Expected fatal configuration error, got \(state)")
        }
        XCTAssertTrue(message.contains("not bundled into this app build"))
    }

    private func makeEmbeddedFixture() throws -> (AppFilesystem, FileMemoryStore) {
        let descriptor = ModelCatalog.current.defaultDescriptor
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let embeddedDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let embeddedModelURL = embeddedDirectoryURL.appendingPathComponent(descriptor.fileName)
        let embeddedMetadataURL = embeddedDirectoryURL.appendingPathComponent("EmbeddedModelMetadata.json")

        try FileManager.default.createDirectory(at: embeddedDirectoryURL, withIntermediateDirectories: true)

        let contents = Data("seed".utf8)
        try contents.write(to: embeddedModelURL)
        let metadata = """
        {
          "modelID": "\(descriptor.id)",
          "fileName": "\(descriptor.fileName)",
          "version": "\(descriptor.version)",
          "expectedFileSizeBytes": \(contents.count),
          "checksum": "embedded-checksum"
        }
        """
        try XCTUnwrap(metadata.data(using: .utf8)).write(to: embeddedMetadataURL)

        let filesystem = AppFilesystem(
            baseURL: baseURL,
            embeddedModelURL: embeddedModelURL,
            embeddedModelMetadataURL: embeddedMetadataURL
        )
        let memoryStore = FileMemoryStore(filesystem: filesystem)
        return (filesystem, memoryStore)
    }
}
