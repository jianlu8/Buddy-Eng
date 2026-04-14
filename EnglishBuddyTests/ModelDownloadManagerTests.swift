import XCTest
@testable import EnglishBuddyCore

@MainActor
final class ModelDownloadManagerTests: XCTestCase {
    func testEnsureBundledBaseReadyMarksModelInstalledImmediately() async throws {
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
        try await memoryStore.load()

        let manager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        try await manager.ensureBundledBaseReady()

        XCTAssertEqual(manager.selectedRecord.status, .installed)
        XCTAssertTrue(manager.selectedRecord.integrityCheckPassed)
        XCTAssertEqual(manager.activeModelReadiness, .ready)
        XCTAssertEqual(manager.modelURL, embeddedModelURL)
    }

    func testRefreshInstallStateUsesBundledBaseModel() async throws {
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
          "version": "embedded-test",
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
        try await memoryStore.load()

        let manager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        await manager.refreshInstallState()

        XCTAssertEqual(manager.selectedModel.id, descriptor.id)
        XCTAssertEqual(manager.selectionState.selectedModelID, descriptor.id)
        XCTAssertEqual(manager.selectedRecord.status, .installed)
        XCTAssertTrue(manager.selectedRecord.integrityCheckPassed)
        XCTAssertTrue(manager.selectedRecord.isEmbeddedInApp)
        XCTAssertEqual(manager.selectedRecord.checksum, "embedded-checksum")
        XCTAssertEqual(manager.modelURL, embeddedModelURL)
    }

    func testDeleteModelKeepsBundledBaseAvailable() async throws {
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
        try await memoryStore.load()

        let manager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        await manager.refreshInstallState()
        try await manager.deleteModel(descriptor.id)

        XCTAssertEqual(manager.selectedRecord.status, .installed)
        XCTAssertTrue(manager.selectedRecord.isEmbeddedInApp)
        XCTAssertEqual(manager.selectionState.selectedModelID, descriptor.id)
    }

    func testRefreshNormalizesInvalidSelectionToBundledDefault() async throws {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let descriptor = ModelCatalog.current.defaultDescriptor
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
        try await memoryStore.load()
        try await memoryStore.updateModelSelectionState(
            ModelSelectionState(selectedModelID: "qwen-3_5-placeholder", defaultModelID: "missing-default")
        )

        let manager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        await manager.refreshInstallState()

        XCTAssertEqual(manager.selectionState.defaultModelID, descriptor.id)
        XCTAssertEqual(manager.selectionState.selectedModelID, descriptor.id)
    }

    func testRepairCorruptionMarksBundledRecordCorrupted() async throws {
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
          "expectedFileSizeBytes": \(contents.count + 10),
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
        try await memoryStore.load()

        let manager = ModelDownloadManager(filesystem: filesystem, memoryStore: memoryStore)
        await manager.refreshInstallState()
        await manager.repairCorruptionIfNeeded()

        XCTAssertEqual(manager.selectedRecord.status, .corrupted)
        XCTAssertFalse(manager.selectedRecord.integrityCheckPassed)
        XCTAssertNotNil(manager.selectedRecord.failureReason)
    }
}
