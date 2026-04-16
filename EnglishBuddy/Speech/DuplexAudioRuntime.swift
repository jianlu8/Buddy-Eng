import AVFoundation
import UIKit

@MainActor
final class DuplexAudioRuntime: NSObject, DuplexAudioRuntimeProtocol {
    var onInterruptionReason: (@MainActor (SpeechInterruptionReason) -> Void)?

    var onListeningSuspended: (@MainActor (SpeechInterruptionReason) -> Void)?
    var onRecoveryRequested: (@MainActor () async -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruptionNotification(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChangeNotification),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackgroundNotification),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForegroundNotification),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func prepareAudioSessionForCall() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setPreferredIOBufferDuration(0.0058)
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
    }

    func recoverAudioAfterInterruption() async throws {
        try await prepareAudioSessionForCall()
    }

    func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func configureVoiceProcessingIfAvailable(for inputNode: AVAudioInputNode) {
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            #if DEBUG
            print("DuplexAudioRuntime: voice processing unavailable: \(error.localizedDescription)")
            #endif
        }
    }

    @objc nonisolated private func handleAudioInterruptionNotification(_ notification: Notification) {
        let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        Task { @MainActor [weak self] in
            self?.handleAudioInterruption(typeRawValue: rawValue)
        }
    }

    @objc nonisolated private func handleRouteChangeNotification() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onInterruptionReason?(.routeChange)
            if let onRecoveryRequested = self.onRecoveryRequested {
                await onRecoveryRequested()
            }
        }
    }

    @objc nonisolated private func handleDidEnterBackgroundNotification() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onListeningSuspended?(.backgrounded)
        }
    }

    @objc nonisolated private func handleWillEnterForegroundNotification() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let onRecoveryRequested = self.onRecoveryRequested {
                await onRecoveryRequested()
            }
        }
    }

    private func handleAudioInterruption(typeRawValue: UInt?) {
        guard let rawValue = typeRawValue,
              let type = AVAudioSession.InterruptionType(rawValue: rawValue) else {
            return
        }

        switch type {
        case .began:
            onListeningSuspended?(.systemInterruption)
        case .ended:
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let onRecoveryRequested = self.onRecoveryRequested {
                    await onRecoveryRequested()
                }
            }
        @unknown default:
            break
        }
    }
}
