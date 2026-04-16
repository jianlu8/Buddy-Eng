import Foundation

struct AppFilesystem {
    let rootURL: URL
    private let resourceBundle: Bundle
    private let embeddedModelURLOverrides: [String: URL]
    private let embeddedModelMetadataURLOverrides: [String: URL]
    private let embeddedSpeechAssetURLOverrides: [String: URL]

    init(
        baseURL: URL? = nil,
        resourceBundle: Bundle = .main,
        embeddedModelURL: URL? = nil,
        embeddedModelMetadataURL: URL? = nil,
        embeddedSpeechAssetURLs: [String: URL] = [:]
    ) {
        if let baseURL {
            rootURL = baseURL
        } else {
            rootURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("EnglishBuddy", isDirectory: true)
        }
        self.resourceBundle = resourceBundle
        var modelOverrides: [String: URL] = [:]
        var metadataOverrides: [String: URL] = [:]
        if let embeddedModelURL {
            modelOverrides[ModelCatalog.current.defaultSelectionState.defaultModelID] = embeddedModelURL
        }
        if let embeddedModelMetadataURL {
            metadataOverrides[ModelCatalog.current.defaultSelectionState.defaultModelID] = embeddedModelMetadataURL
        }
        embeddedModelURLOverrides = modelOverrides
        embeddedModelMetadataURLOverrides = metadataOverrides
        embeddedSpeechAssetURLOverrides = embeddedSpeechAssetURLs
    }

    var snapshotURL: URL {
        rootURL.appendingPathComponent("memory-snapshot.json")
    }

    var userDataDirectoryURL: URL {
        rootURL.appendingPathComponent("UserData", isDirectory: true)
    }

    var modelStateDirectoryURL: URL {
        rootURL.appendingPathComponent("ModelState", isDirectory: true)
    }

    var assetStateDirectoryURL: URL {
        rootURL.appendingPathComponent("AssetState", isDirectory: true)
    }

    var migrationsDirectoryURL: URL {
        rootURL.appendingPathComponent("Migrations", isDirectory: true)
    }

    var validationDirectoryURL: URL {
        rootURL.appendingPathComponent("Validation", isDirectory: true)
    }

    var userDataSnapshotURL: URL {
        userDataDirectoryURL.appendingPathComponent("user-data-v2.json")
    }

    var modelStateSnapshotURL: URL {
        modelStateDirectoryURL.appendingPathComponent("model-state-v2.json")
    }

    var assetStateSnapshotURL: URL {
        assetStateDirectoryURL.appendingPathComponent("asset-state-v2.json")
    }

    var migrationReceiptURL: URL {
        migrationsDirectoryURL.appendingPathComponent("latest-migration.json")
    }

    var modelsDirectoryURL: URL {
        rootURL.appendingPathComponent("Models", isDirectory: true)
    }

    var portraitCacheDirectoryURL: URL {
        rootURL.appendingPathComponent("PortraitCache", isDirectory: true)
    }

    var speechAssetsDirectoryURL: URL {
        rootURL.appendingPathComponent("SpeechAssets", isDirectory: true)
    }

    var liteRTCacheDirectoryURL: URL {
        modelStateDirectoryURL.appendingPathComponent("LiteRTCache", isDirectory: true)
    }

    func modelDirectoryURL(for descriptor: ModelDescriptor) -> URL {
        modelsDirectoryURL.appendingPathComponent(descriptor.id, isDirectory: true)
    }

    func downloadedModelURL(for descriptor: ModelDescriptor) -> URL {
        modelDirectoryURL(for: descriptor).appendingPathComponent(descriptor.fileName)
    }

    func localModelMetadataURL(for descriptor: ModelDescriptor) -> URL {
        modelDirectoryURL(for: descriptor).appendingPathComponent("EmbeddedModelMetadata.json")
    }

    func stagedDownloadURL(for descriptor: ModelDescriptor) -> URL {
        modelDirectoryURL(for: descriptor).appendingPathComponent(descriptor.fileName + ".download")
    }

    var embeddedModelsDirectoryURL: URL? {
        resourceBundle.resourceURL?.appendingPathComponent("EmbeddedModels", isDirectory: true)
    }

    var embeddedSpeechAssetsDirectoryURL: URL? {
        resourceBundle.resourceURL?.appendingPathComponent("SpeechAssets", isDirectory: true)
    }

    func embeddedModelURL(for descriptor: ModelDescriptor) -> URL? {
        if let override = embeddedModelURLOverrides[descriptor.id] {
            return override
        }
        if let nestedURL = resourceBundle.url(
            forResource: descriptor.fileName,
            withExtension: nil,
            subdirectory: "EmbeddedModels/\(descriptor.id)"
        ) {
            return nestedURL
        }
        return resourceBundle.url(
            forResource: descriptor.fileName,
            withExtension: nil,
            subdirectory: "EmbeddedModels"
        )
    }

    func embeddedModelMetadataURL(for descriptor: ModelDescriptor) -> URL? {
        if let override = embeddedModelMetadataURLOverrides[descriptor.id] {
            return override
        }
        if let nestedURL = resourceBundle.url(
            forResource: "EmbeddedModelMetadata",
            withExtension: "json",
            subdirectory: "EmbeddedModels/\(descriptor.id)"
        ) {
            return nestedURL
        }
        return resourceBundle.url(
            forResource: "EmbeddedModelMetadata",
            withExtension: "json",
            subdirectory: "EmbeddedModels"
        )
    }

    func embeddedSpeechAssetURL(for assetID: String) -> URL? {
        if let override = embeddedSpeechAssetURLOverrides[assetID] {
            return override
        }

        guard let embeddedSpeechAssetsDirectoryURL else { return nil }
        let directURL = embeddedSpeechAssetsDirectoryURL.appendingPathComponent(assetID)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }

        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: embeddedSpeechAssetsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidates.first { candidate in
            let name = candidate.deletingPathExtension().lastPathComponent
            return name == assetID || candidate.lastPathComponent == assetID
        }
    }

    func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userDataDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelStateDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetStateDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: migrationsDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: validationDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: liteRTCacheDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: portraitCacheDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: speechAssetsDirectoryURL, withIntermediateDirectories: true)
    }

    func prepareDirectories(for descriptor: ModelDescriptor) throws {
        try prepareDirectories()
        try FileManager.default.createDirectory(at: modelDirectoryURL(for: descriptor), withIntermediateDirectories: true)
    }
}
