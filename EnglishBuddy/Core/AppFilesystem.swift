import Foundation

struct AppFilesystem {
    let rootURL: URL
    private let resourceBundle: Bundle
    private let embeddedModelURLOverrides: [String: URL]
    private let embeddedModelMetadataURLOverrides: [String: URL]

    init(
        baseURL: URL? = nil,
        resourceBundle: Bundle = .main,
        embeddedModelURL: URL? = nil,
        embeddedModelMetadataURL: URL? = nil
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
    }

    var snapshotURL: URL {
        rootURL.appendingPathComponent("memory-snapshot.json")
    }

    var modelsDirectoryURL: URL {
        rootURL.appendingPathComponent("Models", isDirectory: true)
    }

    func modelDirectoryURL(for descriptor: ModelDescriptor) -> URL {
        modelsDirectoryURL.appendingPathComponent(descriptor.id, isDirectory: true)
    }

    func downloadedModelURL(for descriptor: ModelDescriptor) -> URL {
        modelDirectoryURL(for: descriptor).appendingPathComponent(descriptor.fileName)
    }

    func stagedDownloadURL(for descriptor: ModelDescriptor) -> URL {
        modelDirectoryURL(for: descriptor).appendingPathComponent(descriptor.fileName + ".download")
    }

    var embeddedModelsDirectoryURL: URL? {
        resourceBundle.resourceURL?.appendingPathComponent("EmbeddedModels", isDirectory: true)
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

    func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)
    }

    func prepareDirectories(for descriptor: ModelDescriptor) throws {
        try prepareDirectories()
        try FileManager.default.createDirectory(at: modelDirectoryURL(for: descriptor), withIntermediateDirectories: true)
    }
}
