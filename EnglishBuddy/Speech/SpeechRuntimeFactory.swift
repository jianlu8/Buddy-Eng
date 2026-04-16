import Foundation

@MainActor
struct SpeechRuntimeFactory {
    typealias BundledASRRuntimeBuilder = @MainActor (SpeechRuntimeDescriptor, DuplexAudioRuntime) -> any ASRRuntimeProtocol
    typealias BundledTTSRuntimeBuilder = @MainActor (SpeechRuntimeDescriptor) -> any TTSRuntimeProtocol

    let audioRuntime: DuplexAudioRuntime
    let assetRegistry: BundledSpeechAssetRegistry
    private let bundledASRRuntimeBuilder: BundledASRRuntimeBuilder?
    private let bundledTTSRuntimeBuilder: BundledTTSRuntimeBuilder?

    init(
        audioRuntime: DuplexAudioRuntime = DuplexAudioRuntime(),
        assetRegistry: BundledSpeechAssetRegistry,
        bundledASRRuntimeBuilder: BundledASRRuntimeBuilder? = nil,
        bundledTTSRuntimeBuilder: BundledTTSRuntimeBuilder? = nil
    ) {
        self.audioRuntime = audioRuntime
        self.assetRegistry = assetRegistry
        self.bundledASRRuntimeBuilder = bundledASRRuntimeBuilder
        self.bundledTTSRuntimeBuilder = bundledTTSRuntimeBuilder
    }

    func makeASRRuntime(
        descriptor: SpeechRuntimeDescriptor = SpeechRuntimeStatusSnapshot.fallbackDefault.asr
    ) -> any ASRRuntimeProtocol {
        let normalizedDescriptor = normalizeASRDescriptor(descriptor)
        switch normalizedDescriptor.activeRuntimeID {
        case "sherpa-onnx-asr":
            if let bundledASRRuntimeBuilder {
                return bundledASRRuntimeBuilder(normalizedDescriptor, audioRuntime)
            }
            return BundledASRRuntime(
                descriptor: normalizedDescriptor,
                audioRuntime: audioRuntime
            )
        default:
            return SpeechFallbackASRRuntime(audioRuntime: audioRuntime)
        }
    }

    func makeTTSRuntime(
        descriptor: SpeechRuntimeDescriptor = SpeechRuntimeStatusSnapshot.fallbackDefault.tts
    ) -> any TTSRuntimeProtocol {
        let normalizedDescriptor = normalizeTTSDescriptor(descriptor)
        switch normalizedDescriptor.activeRuntimeID {
        case "kokoro-tts", "piper-tts":
            if let bundledTTSRuntimeBuilder {
                return bundledTTSRuntimeBuilder(normalizedDescriptor)
            }
            return BundledTTSRuntime(descriptor: normalizedDescriptor)
        default:
            return SpeechFallbackTTSRuntime()
        }
    }

    func asrRuntimeDescriptor(localeIdentifier: String) -> SpeechRuntimeDescriptor {
        normalizeASRDescriptor(
            assetRegistry.asrRuntimeDescriptor(localeIdentifier: localeIdentifier)
        )
    }

    func ttsRuntimeDescriptor(voiceBundle: VoiceBundle) -> SpeechRuntimeDescriptor {
        normalizeTTSDescriptor(
            assetRegistry.ttsRuntimeDescriptor(voiceBundle: voiceBundle)
        )
    }

    func runtimeStatus(
        conversationLanguage: LanguageProfile,
        voiceBundle: VoiceBundle
    ) -> SpeechRuntimeStatusSnapshot {
        let snapshot = assetRegistry.runtimeStatus(
            conversationLanguage: conversationLanguage,
            voiceBundle: voiceBundle
        )
        return normalize(snapshot: snapshot)
    }

    func normalize(snapshot: SpeechRuntimeStatusSnapshot) -> SpeechRuntimeStatusSnapshot {
        SpeechRuntimeStatusSnapshot(
            asr: normalizeASRDescriptor(snapshot.asr),
            tts: normalizeTTSDescriptor(snapshot.tts)
        )
    }

    private func normalizeASRDescriptor(_ descriptor: SpeechRuntimeDescriptor) -> SpeechRuntimeDescriptor {
        guard descriptor.activeRuntimeID == "sherpa-onnx-asr" else {
            return descriptor
        }

        guard BundledASRRuntime.supportsTrueBundledExecution else {
            return SpeechRuntimeDescriptor(
                activeRuntimeID: "system-asr-fallback",
                preferredAssetID: descriptor.preferredAssetID,
                assetAvailability: .fallbackOnly,
                fallbackReason: "Bundled sherpa-onnx assets are staged, but this build still routes ASR through the debug fallback runtime."
            )
        }

        return descriptor
    }

    private func normalizeTTSDescriptor(_ descriptor: SpeechRuntimeDescriptor) -> SpeechRuntimeDescriptor {
        guard descriptor.activeRuntimeID == "kokoro-tts" || descriptor.activeRuntimeID == "piper-tts" else {
            return descriptor
        }

        guard BundledTTSRuntime.supportsTrueBundledExecution else {
            return SpeechRuntimeDescriptor(
                activeRuntimeID: "system-tts-fallback",
                preferredAssetID: descriptor.preferredAssetID,
                assetAvailability: .fallbackOnly,
                fallbackReason: "Bundled \(descriptor.activeRuntimeID) assets are staged, but this build still routes TTS through the debug fallback runtime."
            )
        }

        return descriptor
    }
}
