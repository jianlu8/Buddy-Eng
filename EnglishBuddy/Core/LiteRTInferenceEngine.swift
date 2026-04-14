import Foundation

enum InferenceError: LocalizedError {
    case notPrepared
    case bridgeFailure(String)
    case streamTimedOut

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "The LiteRT engine is not prepared yet."
        case let .bridgeFailure(message):
            return message
        case .streamTimedOut:
            return "The local model stopped responding before finishing the reply."
        }
    }
}

private final class LiteRTBridgeBox: @unchecked Sendable {
    let bridge: LiteRTBridge

    init(bridge: LiteRTBridge) {
        self.bridge = bridge
    }
}

@MainActor
final class LiteRTInferenceEngine: NSObject, InferenceEngineProtocol {
    private let bridgeBox = LiteRTBridgeBox(bridge: LiteRTBridge())
    private let bridgeQueue = DispatchQueue(label: "EnglishBuddy.LiteRTInferenceEngine", qos: .userInitiated)
    private var prepared = false
    private var preparedModelURL: URL?
    private var preparedBackend: InferenceBackendPreference?
    private var activeStreamCoordinator: InferenceStreamCoordinator?

    func prepare(modelURL: URL, backend: InferenceBackendPreference) async throws {
        if prepared, preparedModelURL == modelURL, preparedBackend == backend {
            return
        }

        let bridgeBox = self.bridgeBox
        let bridgeBackend = LiteRTBridgeBackend(rawValue: backend == .gpu ? 0 : 1) ?? LiteRTBridgeBackend(rawValue: 0)!
        do {
            try await performOnBridgeQueue {
                try bridgeBox.bridge.prepare(withModelURL: modelURL, backend: bridgeBackend)
            }
        } catch {
            prepared = false
            preparedModelURL = nil
            preparedBackend = nil
            throw error
        }
        prepared = true
        preparedModelURL = modelURL
        preparedBackend = backend
    }

    func startConversation(preface: ConversationPreface, memoryContext: String, mode: ConversationMode) async throws {
        guard prepared else { throw InferenceError.notPrepared }

        let bridgeBox = self.bridgeBox
        try await performOnBridgeQueue {
            try bridgeBox.bridge.startConversation(
                withSystemPrompt: preface.systemPrompt,
                memoryContext: memoryContext,
                mode: mode.rawValue
            )
        }
    }

    func send(text: String) async throws -> String {
        try await sendStreaming(text: text) { _ in }
    }

    func sendStreaming(text: String, onToken: @escaping @MainActor (String) -> Void) async throws -> String {
        guard prepared else { throw InferenceError.notPrepared }
        let bridgeBox = self.bridgeBox
        let response: String = try await withCheckedThrowingContinuation { continuation in
            let coordinator = InferenceStreamCoordinator(
                tokenHandler: onToken,
                completion: { result in
                    continuation.resume(with: result)
                },
                onTerminal: { [weak self] in
                    Task { @MainActor in
                        self?.activeStreamCoordinator = nil
                    }
                }
            )
            activeStreamCoordinator = coordinator
            coordinator.startWatchdog()

            bridgeQueue.async {
                do {
                    try bridgeBox.bridge.sendText(text, onToken: { token, isFinal, error in
                        if let error {
                            let nsError = error as NSError
                            if nsError.domain == "LiteRTBridge", nsError.code == 499 {
                                coordinator.cancel()
                            } else {
                                coordinator.fail(error)
                            }
                            return
                        }

                        if isFinal {
                            coordinator.finish()
                        } else if token.isEmpty == false {
                            coordinator.receive(token: token)
                        }
                    })
                } catch {
                    coordinator.fail(error)
                }
            }
        }

        return response
    }

    func cancelCurrentResponse() {
        activeStreamCoordinator?.cancel()
        let bridgeBox = self.bridgeBox
        bridgeQueue.async {
            bridgeBox.bridge.cancelCurrentResponse()
        }
    }

    private func performOnBridgeQueue<T>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            bridgeQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
