import XCTest
@testable import EnglishBuddyCore

final class BundledSpeechAssetRegistryTests: XCTestCase {
    func testRegistryDefaultLoadsIntegrationAndBridgeAvailabilityFromBuildFacts() throws {
        let tempDirectory = try makeSpeechAssetsDirectory()
        let asrURL = tempDirectory.appendingPathComponent("sherpa-onnx-en-us-streaming", isDirectory: true)
        let ttsURL = tempDirectory.appendingPathComponent("kokoro-multi-lang-v1_0", isDirectory: true)
        try createPayloadDirectory(at: asrURL, payloadFileName: "tokens.txt", contents: "hello")
        try createPayloadDirectory(at: ttsURL, payloadFileName: "model.onnx", contents: "voice")
        try writeManifest(
            to: tempDirectory,
            assets: [
                manifestRecord(
                    assetID: "sherpa-onnx-en-us-streaming",
                    runtimeType: .asr,
                    runtimeID: "sherpa-onnx-asr",
                    locale: "en-US",
                    payloadURL: asrURL
                ),
                manifestRecord(
                    assetID: "kokoro-multi-lang-v1_0",
                    runtimeType: .tts,
                    runtimeID: "kokoro-tts",
                    locale: "en-US",
                    supportedVoiceBundleIDs: ["nova-voice", "lyra-voice"],
                    modelFamily: "kokoro",
                    payloadURL: ttsURL
                )
            ]
        )
        try writeBuildFacts(
            to: tempDirectory,
            sherpaOnnxEnabled: true,
            kokoroEnabled: true,
            piperEnabled: false,
            sherpaOnnxBridgeLinked: true,
            kokoroBridgeLinked: true,
            piperBridgeLinked: false
        )

        let filesystem = AppFilesystem(baseURL: tempDirectory.deletingLastPathComponent())
        let registry = BundledSpeechAssetRegistry(filesystem: filesystem)

        let snapshot = registry.runtimeStatus(
            conversationLanguage: LanguageCatalog.english,
            voiceBundle: VoiceCatalog.defaultBundle(
                for: CharacterCatalog.flagship.id,
                languageID: LanguageCatalog.english.id
            )
        )

        XCTAssertEqual(snapshot.asr.activeRuntimeID, "sherpa-onnx-asr")
        XCTAssertEqual(snapshot.asr.assetAvailability, .bundledReady)
        XCTAssertEqual(snapshot.tts.activeRuntimeID, "kokoro-tts")
        XCTAssertEqual(snapshot.tts.assetAvailability, .bundledReady)
    }

    func testMissingBundledAssetsFallBackToSystemRuntime() throws {
        let filesystem = AppFilesystem(
            baseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let registry = BundledSpeechAssetRegistry(filesystem: filesystem)

        let snapshot = registry.runtimeStatus(
            conversationLanguage: LanguageCatalog.english,
            voiceBundle: VoiceCatalog.defaultBundle(
                for: CharacterCatalog.flagship.id,
                languageID: LanguageCatalog.english.id
            )
        )

        XCTAssertEqual(snapshot.asr.activeRuntimeID, "system-asr-fallback")
        XCTAssertEqual(snapshot.asr.assetAvailability, .bundledMissing)
        XCTAssertEqual(snapshot.tts.activeRuntimeID, "system-tts-fallback")
        XCTAssertEqual(snapshot.tts.assetAvailability, .bundledMissing)
        XCTAssertTrue(snapshot.usesFallbackRuntime)
    }

    func testBundledAssetsStayFallbackOnlyWhenRuntimeIsNotLinked() throws {
        let tempDirectory = try makeSpeechAssetsDirectory()
        let asrURL = tempDirectory.appendingPathComponent("sherpa-onnx-en-us-streaming", isDirectory: true)
        let ttsURL = tempDirectory.appendingPathComponent("kokoro-multi-lang-v1_0", isDirectory: true)
        try createPayloadDirectory(at: asrURL, payloadFileName: "tokens.txt", contents: "hello")
        try createPayloadDirectory(at: ttsURL, payloadFileName: "model.onnx", contents: "voice")
        try writeManifest(
            to: tempDirectory,
            assets: [
                manifestRecord(
                    assetID: "sherpa-onnx-en-us-streaming",
                    runtimeType: .asr,
                    runtimeID: "sherpa-onnx-asr",
                    locale: "en-US",
                    payloadURL: asrURL
                ),
                manifestRecord(
                    assetID: "kokoro-multi-lang-v1_0",
                    runtimeType: .tts,
                    runtimeID: "kokoro-tts",
                    locale: "en-US",
                    supportedVoiceBundleIDs: ["nova-voice", "lyra-voice"],
                    modelFamily: "kokoro",
                    payloadURL: ttsURL
                )
            ]
        )

        let filesystem = AppFilesystem(baseURL: tempDirectory.deletingLastPathComponent())
        let registry = BundledSpeechAssetRegistry(
            filesystem: filesystem,
            integrationAvailability: SpeechRuntimeIntegrationAvailability(
                sherpaOnnxEnabled: true,
                kokoroEnabled: true,
                piperEnabled: false
            ),
            bridgeAvailability: .current
        )

        let snapshot = registry.runtimeStatus(
            conversationLanguage: LanguageCatalog.english,
            voiceBundle: VoiceCatalog.defaultBundle(
                for: CharacterCatalog.flagship.id,
                languageID: LanguageCatalog.english.id
            )
        )

        XCTAssertEqual(snapshot.asr.activeRuntimeID, "system-asr-fallback")
        XCTAssertEqual(snapshot.asr.assetAvailability, .fallbackOnly)
        XCTAssertEqual(snapshot.tts.activeRuntimeID, "system-tts-fallback")
        XCTAssertEqual(snapshot.tts.assetAvailability, .fallbackOnly)
        XCTAssertTrue(snapshot.usesFallbackRuntime)
    }

    func testBundledAssetsBecomePreferredWhenIntegrationIsEnabledAndRuntimeIsLinked() throws {
        let tempDirectory = try makeSpeechAssetsDirectory()
        let asrURL = tempDirectory.appendingPathComponent("sherpa-onnx-en-us-streaming", isDirectory: true)
        let ttsURL = tempDirectory.appendingPathComponent("kokoro-multi-lang-v1_0", isDirectory: true)
        try createPayloadDirectory(at: asrURL, payloadFileName: "tokens.txt", contents: "hello")
        try createPayloadDirectory(at: ttsURL, payloadFileName: "model.onnx", contents: "voice")
        try writeManifest(
            to: tempDirectory,
            assets: [
                manifestRecord(
                    assetID: "sherpa-onnx-en-us-streaming",
                    runtimeType: .asr,
                    runtimeID: "sherpa-onnx-asr",
                    locale: "en-US",
                    payloadURL: asrURL
                ),
                manifestRecord(
                    assetID: "kokoro-multi-lang-v1_0",
                    runtimeType: .tts,
                    runtimeID: "kokoro-tts",
                    locale: "en-US",
                    supportedVoiceBundleIDs: ["nova-voice", "lyra-voice"],
                    modelFamily: "kokoro",
                    payloadURL: ttsURL
                )
            ]
        )

        let filesystem = AppFilesystem(baseURL: tempDirectory.deletingLastPathComponent())
        let registry = BundledSpeechAssetRegistry(
            filesystem: filesystem,
            integrationAvailability: SpeechRuntimeIntegrationAvailability(
                sherpaOnnxEnabled: true,
                kokoroEnabled: true,
                piperEnabled: false
            ),
            bridgeAvailability: BundledSpeechAssetRegistry.RuntimeBridgeAvailability(
                sherpaOnnxLinked: true,
                kokoroLinked: true,
                piperLinked: false
            )
        )

        let snapshot = registry.runtimeStatus(
            conversationLanguage: LanguageCatalog.english,
            voiceBundle: VoiceCatalog.defaultBundle(
                for: CharacterCatalog.flagship.id,
                languageID: LanguageCatalog.english.id
            )
        )

        XCTAssertEqual(snapshot.asr.activeRuntimeID, "sherpa-onnx-asr")
        XCTAssertEqual(snapshot.asr.assetAvailability, .bundledReady)
        XCTAssertEqual(snapshot.tts.activeRuntimeID, "kokoro-tts")
        XCTAssertEqual(snapshot.tts.assetAvailability, .bundledReady)
        XCTAssertFalse(snapshot.usesFallbackRuntime)
    }

    func testManifestSizeMismatchForcesBundledMissing() throws {
        let tempDirectory = try makeSpeechAssetsDirectory()
        let asrURL = tempDirectory.appendingPathComponent("sherpa-onnx-en-us-streaming", isDirectory: true)
        try createPayloadDirectory(at: asrURL, payloadFileName: "tokens.txt", contents: "hello")
        let wrongSizedRecord = BundledSpeechAssetManifest.AssetRecord(
            assetID: "sherpa-onnx-en-us-streaming",
            runtimeType: .asr,
            runtimeID: "sherpa-onnx-asr",
            modelFamily: nil,
            version: "1",
            checksum: nil,
            size: 999,
            locale: "en-US",
            voiceBundleID: nil,
            supportedVoiceBundleIDs: nil,
            speakerInventoryVersion: nil,
            relativePath: "sherpa-onnx-en-us-streaming",
            required: true
        )
        try writeManifest(to: tempDirectory, assets: [wrongSizedRecord])

        let filesystem = AppFilesystem(baseURL: tempDirectory.deletingLastPathComponent())
        let registry = BundledSpeechAssetRegistry(filesystem: filesystem)

        let descriptor = registry.asrRuntimeDescriptor(localeIdentifier: "en-US")
        XCTAssertEqual(descriptor.activeRuntimeID, "system-asr-fallback")
        XCTAssertEqual(descriptor.assetAvailability, .bundledMissing)
        XCTAssertEqual(
            descriptor.fallbackReason,
            "Speech asset sherpa-onnx-en-us-streaming has size 5 bytes, expected 999 bytes."
        )
    }

    private func makeSpeechAssetsDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let speechAssets = root.appendingPathComponent("SpeechAssets", isDirectory: true)
        try FileManager.default.createDirectory(at: speechAssets, withIntermediateDirectories: true)
        return speechAssets
    }

    private func createPayloadDirectory(
        at url: URL,
        payloadFileName: String,
        contents: String
    ) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let payloadURL = url.appendingPathComponent(payloadFileName)
        guard let data = contents.data(using: .utf8) else {
            XCTFail("Failed to encode payload contents.")
            return
        }
        try data.write(to: payloadURL)
    }

    private func manifestRecord(
        assetID: String,
        runtimeType: BundledSpeechAssetManifest.RuntimeType,
        runtimeID: String,
        locale: String,
        voiceBundleID: String? = nil,
        supportedVoiceBundleIDs: [String]? = nil,
        modelFamily: String? = nil,
        payloadURL: URL
    ) -> BundledSpeechAssetManifest.AssetRecord {
        BundledSpeechAssetManifest.AssetRecord(
            assetID: assetID,
            runtimeType: runtimeType,
            runtimeID: runtimeID,
            modelFamily: modelFamily,
            version: "1",
            checksum: nil,
            size: payloadSize(at: payloadURL),
            locale: locale,
            voiceBundleID: voiceBundleID,
            supportedVoiceBundleIDs: supportedVoiceBundleIDs,
            speakerInventoryVersion: "v1",
            relativePath: payloadURL.lastPathComponent,
            required: true
        )
    }

    private func payloadSize(at url: URL) -> Int64 {
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var total: Int64 = 0
        while let item = enumerator?.nextObject() as? URL {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    private func writeManifest(
        to speechAssetsDirectory: URL,
        assets: [BundledSpeechAssetManifest.AssetRecord]
    ) throws {
        let manifest = BundledSpeechAssetManifest(
            manifestVersion: 1,
            generatedAt: nil,
            assets: assets
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestURL = speechAssetsDirectory.appendingPathComponent(BundledSpeechAssetManifest.fileName)
        try encoder.encode(manifest).write(to: manifestURL)
    }

    private func writeBuildFacts(
        to speechAssetsDirectory: URL,
        sherpaOnnxEnabled: Bool,
        kokoroEnabled: Bool,
        piperEnabled: Bool,
        sherpaOnnxBridgeLinked: Bool,
        kokoroBridgeLinked: Bool,
        piperBridgeLinked: Bool,
        strictReleaseLane: Bool = false,
        allowsRuntimeFallback: Bool = true
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let facts = SpeechRuntimeBuildFacts(
            sherpaOnnxEnabled: sherpaOnnxEnabled,
            kokoroEnabled: kokoroEnabled,
            piperEnabled: piperEnabled,
            sherpaOnnxBridgeLinked: sherpaOnnxBridgeLinked,
            kokoroBridgeLinked: kokoroBridgeLinked,
            piperBridgeLinked: piperBridgeLinked,
            strictReleaseLane: strictReleaseLane,
            allowsRuntimeFallback: allowsRuntimeFallback
        )
        let factsURL = speechAssetsDirectory.appendingPathComponent(SpeechRuntimeBuildFacts.fileName)
        try encoder.encode(facts).write(to: factsURL)
    }
}
