import Foundation

struct BundledSpeechAssetManifest: Codable, Equatable, Sendable {
    static let fileName = "Manifest.json"

    enum RuntimeType: String, Codable, Equatable, Sendable {
        case asr
        case tts
    }

    struct AssetRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
        var id: String { assetID }

        var assetID: String
        var runtimeType: RuntimeType
        var runtimeID: String
        var modelFamily: String?
        var version: String?
        var checksum: String?
        var size: Int64?
        var locale: String?
        var voiceBundleID: String?
        var supportedVoiceBundleIDs: [String]?
        var speakerInventoryVersion: String?
        var relativePath: String?
        var required: Bool?

        var resolvedRelativePath: String {
            let trimmed = relativePath?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? assetID : trimmed
        }

        var resolvedSupportedVoiceBundleIDs: [String] {
            let supported = (supportedVoiceBundleIDs ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            if supported.isEmpty == false {
                return supported
            }
            let legacy = voiceBundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return legacy.isEmpty ? [] : [legacy]
        }
    }

    var manifestVersion: Int
    var generatedAt: Date?
    var assets: [AssetRecord]

    func record(for assetID: String) -> AssetRecord? {
        assets.first(where: { $0.assetID == assetID })
    }

    static func load(from directoryURL: URL?) -> BundledSpeechAssetManifest? {
        guard let directoryURL else { return nil }

        let manifestURL = directoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BundledSpeechAssetManifest.self, from: data)
    }
}

struct BundledSpeechAssetRegistry {
    struct RuntimeBridgeAvailability {
        var sherpaOnnxLinked: Bool
        var kokoroLinked: Bool
        var piperLinked: Bool

        static var current: RuntimeBridgeAvailability {
            resolve(
                from: Bundle.main.resourceURL?.appendingPathComponent("SpeechAssets", isDirectory: true)
            )
        }

        static func resolve(from directoryURL: URL?) -> RuntimeBridgeAvailability {
            let facts = SpeechRuntimeBuildFacts.resolve(from: directoryURL)
            return RuntimeBridgeAvailability(
                sherpaOnnxLinked: facts.sherpaOnnxBridgeLinked,
                kokoroLinked: facts.kokoroBridgeLinked,
                piperLinked: facts.piperBridgeLinked
            )
        }
    }

    private struct AssetAudit {
        var record: BundledSpeechAssetManifest.AssetRecord?
        var payloadURL: URL?
        var failureReason: String?

        var isReady: Bool {
            failureReason == nil && record != nil && payloadURL != nil
        }
    }

    private let filesystem: AppFilesystem
    private let integrationAvailability: SpeechRuntimeIntegrationAvailability
    private let bridgeAvailability: RuntimeBridgeAvailability

    init(
        filesystem: AppFilesystem,
        integrationAvailability: SpeechRuntimeIntegrationAvailability? = nil,
        bridgeAvailability: RuntimeBridgeAvailability? = nil
    ) {
        let manifestDirectoryURL = Self.resolveManifestDirectoryURL(for: filesystem)
        self.filesystem = filesystem
        self.integrationAvailability = integrationAvailability
            ?? SpeechRuntimeIntegrationAvailability.resolve(from: manifestDirectoryURL)
        self.bridgeAvailability = bridgeAvailability
            ?? RuntimeBridgeAvailability.resolve(from: manifestDirectoryURL)
    }

    func runtimeStatus(
        conversationLanguage: LanguageProfile,
        voiceBundle: VoiceBundle
    ) -> SpeechRuntimeStatusSnapshot {
        SpeechRuntimeStatusSnapshot(
            asr: asrRuntimeDescriptor(localeIdentifier: conversationLanguage.asrLocale),
            tts: ttsRuntimeDescriptor(voiceBundle: voiceBundle)
        )
    }

    func asrRuntimeDescriptor(localeIdentifier: String) -> SpeechRuntimeDescriptor {
        let language = resolveLanguageProfile(localeIdentifier: localeIdentifier)
        return resolveDescriptor(
            preferredAssetID: language.bundledASRModelID,
            expectedRuntimeType: .asr,
            expectedRuntimeID: "sherpa-onnx-asr",
            expectedLocale: language.asrLocale,
            expectedVoiceBundleID: nil,
            bundledRuntimeEnabled: integrationAvailability.sherpaOnnxEnabled,
            bridgeLinked: bridgeAvailability.sherpaOnnxLinked,
            fallbackRuntimeID: "system-asr-fallback",
            missingReason: "Bundled ASR asset is not packaged in SpeechAssets.",
            disabledReason: "Bundled sherpa-onnx integration is not enabled in this build.",
            unlinkedReason: "Bundled sherpa-onnx runtime is not linked in this build."
        )
    }

    func ttsRuntimeDescriptor(voiceBundle: VoiceBundle) -> SpeechRuntimeDescriptor {
        let family = voiceBundle.ttsModelFamily
        return resolveDescriptor(
            preferredAssetID: voiceBundle.localVoiceAssetID,
            expectedRuntimeType: .tts,
            expectedRuntimeID: family.runtimeID,
            expectedLocale: voiceBundle.languageCode,
            expectedVoiceBundleID: voiceBundle.id,
            bundledRuntimeEnabled: bundledTTSEnabled(for: family),
            bridgeLinked: isTTSBridgeLinked(for: family),
            fallbackRuntimeID: "system-tts-fallback",
            missingReason: "Bundled TTS asset is not packaged in SpeechAssets.",
            disabledReason: "Bundled \(family.displayName) integration is not enabled in this build.",
            unlinkedReason: "Bundled \(family.displayName) runtime is not linked in this build."
        )
    }

    private func resolveDescriptor(
        preferredAssetID: String?,
        expectedRuntimeType: BundledSpeechAssetManifest.RuntimeType,
        expectedRuntimeID: String,
        expectedLocale: String?,
        expectedVoiceBundleID: String?,
        bundledRuntimeEnabled: Bool,
        bridgeLinked: Bool,
        fallbackRuntimeID: String,
        missingReason: String,
        disabledReason: String,
        unlinkedReason: String
    ) -> SpeechRuntimeDescriptor {
        guard let preferredAssetID, preferredAssetID.isEmpty == false else {
            return SpeechRuntimeDescriptor(
                activeRuntimeID: fallbackRuntimeID,
                preferredAssetID: nil,
                assetAvailability: .fallbackOnly,
                fallbackReason: "No bundled speech asset is configured."
            )
        }

        if preferredAssetID.hasPrefix("system-") {
            return SpeechRuntimeDescriptor(
                activeRuntimeID: fallbackRuntimeID,
                preferredAssetID: preferredAssetID,
                assetAvailability: .fallbackOnly,
                fallbackReason: "System speech services are configured as the active fallback path."
            )
        }

        let audit = auditAsset(
            assetID: preferredAssetID,
            expectedRuntimeType: expectedRuntimeType,
            expectedRuntimeID: expectedRuntimeID,
            expectedLocale: expectedLocale,
            expectedVoiceBundleID: expectedVoiceBundleID
        )

        guard audit.isReady else {
            return SpeechRuntimeDescriptor(
                activeRuntimeID: fallbackRuntimeID,
                preferredAssetID: preferredAssetID,
                assetAvailability: .bundledMissing,
                fallbackReason: audit.failureReason ?? missingReason
            )
        }

        guard bundledRuntimeEnabled else {
            return SpeechRuntimeDescriptor(
                activeRuntimeID: fallbackRuntimeID,
                preferredAssetID: preferredAssetID,
                assetAvailability: .fallbackOnly,
                fallbackReason: disabledReason
            )
        }

        guard bridgeLinked else {
            return SpeechRuntimeDescriptor(
                activeRuntimeID: fallbackRuntimeID,
                preferredAssetID: preferredAssetID,
                assetAvailability: .fallbackOnly,
                fallbackReason: unlinkedReason
            )
        }

        return SpeechRuntimeDescriptor(
            activeRuntimeID: expectedRuntimeID,
            preferredAssetID: preferredAssetID,
            assetAvailability: .bundledReady,
            fallbackReason: nil
        )
    }

    private func auditAsset(
        assetID: String,
        expectedRuntimeType: BundledSpeechAssetManifest.RuntimeType,
        expectedRuntimeID: String,
        expectedLocale: String?,
        expectedVoiceBundleID: String?
    ) -> AssetAudit {
        guard let manifest = BundledSpeechAssetManifest.load(from: manifestDirectoryURL) else {
            return AssetAudit(
                record: nil,
                payloadURL: nil,
                failureReason: "SpeechAssets/\(BundledSpeechAssetManifest.fileName) is missing."
            )
        }

        guard let record = manifest.record(for: assetID) else {
            return AssetAudit(
                record: nil,
                payloadURL: nil,
                failureReason: "Speech asset \(assetID) is missing from SpeechAssets/\(BundledSpeechAssetManifest.fileName)."
            )
        }

        guard record.runtimeType == expectedRuntimeType else {
            return AssetAudit(
                record: record,
                payloadURL: nil,
                failureReason: "Speech asset \(assetID) has runtime type \(record.runtimeType.rawValue), expected \(expectedRuntimeType.rawValue)."
            )
        }

        guard record.runtimeID == expectedRuntimeID else {
            return AssetAudit(
                record: record,
                payloadURL: nil,
                failureReason: "Speech asset \(assetID) is bound to runtime \(record.runtimeID), expected \(expectedRuntimeID)."
            )
        }

        if let expectedLocale,
           let recordLocale = record.locale?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           recordLocale.isEmpty == false,
           recordLocale.caseInsensitiveCompare(expectedLocale) != ComparisonResult.orderedSame {
            return AssetAudit(
                record: record,
                payloadURL: nil,
                failureReason: "Speech asset \(assetID) is bound to locale \(recordLocale), expected \(expectedLocale)."
            )
        }

        if let expectedVoiceBundleID,
           record.resolvedSupportedVoiceBundleIDs.isEmpty == false,
           record.resolvedSupportedVoiceBundleIDs.contains(expectedVoiceBundleID) == false {
            return AssetAudit(
                record: record,
                payloadURL: nil,
                failureReason: "Speech asset \(assetID) does not support voice bundle \(expectedVoiceBundleID)."
            )
        }

        guard let payloadURL = payloadURL(for: record) else {
            return AssetAudit(
                record: record,
                payloadURL: nil,
                failureReason: "Speech asset payload \(record.resolvedRelativePath) is missing from SpeechAssets."
            )
        }

        if let expectedSize = record.size,
           let actualSize = recursiveFileSize(at: payloadURL),
           actualSize != expectedSize {
            return AssetAudit(
                record: record,
                payloadURL: payloadURL,
                failureReason: "Speech asset \(assetID) has size \(actualSize) bytes, expected \(expectedSize) bytes."
            )
        }

        return AssetAudit(
            record: record,
            payloadURL: payloadURL,
            failureReason: nil
        )
    }

    private func resolveLanguageProfile(localeIdentifier: String) -> LanguageProfile {
        let trimmed = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let matched = LanguageCatalog.all.first(where: {
            $0.asrLocale.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return matched
        }
        return LanguageCatalog.english
    }

    private func bundledTTSEnabled(for family: TTSModelFamily) -> Bool {
        switch family {
        case .kokoro:
            return integrationAvailability.kokoroEnabled
        case .piperLegacy:
            return integrationAvailability.piperEnabled
        }
    }

    private func isTTSBridgeLinked(for family: TTSModelFamily) -> Bool {
        switch family {
        case .kokoro:
            return bridgeAvailability.kokoroLinked
        case .piperLegacy:
            return bridgeAvailability.piperLinked
        }
    }

    private func payloadURL(for record: BundledSpeechAssetManifest.AssetRecord) -> URL? {
        guard let baseURL = manifestDirectoryURL else { return nil }
        let relativeURL = baseURL.appendingPathComponent(record.resolvedRelativePath, isDirectory: true)
        if FileManager.default.fileExists(atPath: relativeURL.path) {
            return relativeURL
        }
        return candidatePayloadURL(for: record.assetID)
    }

    private func recursiveFileSize(at url: URL) -> Int64? {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if resourceValues?.isDirectory == false {
            return Int64(resourceValues?.fileSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            totalSize += Int64(values?.fileSize ?? 0)
        }
        return totalSize
    }

    private var manifestDirectoryURL: URL? {
        Self.resolveManifestDirectoryURL(for: filesystem)
    }

    private func candidatePayloadURL(for assetID: String) -> URL? {
        if let embedded = filesystem.embeddedSpeechAssetURL(for: assetID) {
            return embedded
        }

        let localURL = filesystem.speechAssetsDirectoryURL.appendingPathComponent(assetID, isDirectory: true)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        let fileURL = filesystem.speechAssetsDirectoryURL.appendingPathComponent(assetID, isDirectory: false)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        return nil
    }

    private static func resolveManifestDirectoryURL(for filesystem: AppFilesystem) -> URL? {
        if let embedded = filesystem.embeddedSpeechAssetsDirectoryURL,
           FileManager.default.fileExists(atPath: embedded.path) {
            return embedded
        }
        if FileManager.default.fileExists(atPath: filesystem.speechAssetsDirectoryURL.path) {
            return filesystem.speechAssetsDirectoryURL
        }
        return nil
    }
}
