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
    private let filesystem: AppFilesystem
    private let bridgeBox = LiteRTBridgeBox(bridge: LiteRTBridge())
    private let bridgeQueue = DispatchQueue(label: "EnglishBuddy.LiteRTInferenceEngine", qos: .userInitiated)
    private var prepared = false
    private var preparedModelURL: URL?
    private var preparedBackend: InferenceBackendPreference?
    private var activeStreamCoordinator: InferenceStreamCoordinator?
    private var lastSystemPrompt: String?
    private var lastMemoryContext: String?
    private var lastMode: ConversationMode?

    init(filesystem: AppFilesystem = AppFilesystem()) {
        self.filesystem = filesystem
        super.init()
    }

    func prepare(modelURL: URL, backend: InferenceBackendPreference) async throws {
        if prepared, preparedModelURL == modelURL, preparedBackend == backend {
            return
        }

        let bridgeBox = self.bridgeBox
        let bridgeBackend = LiteRTBridgeBackend(rawValue: backend == .gpu ? 0 : 1) ?? LiteRTBridgeBackend(rawValue: 0)!
        let cacheDirectoryURL = filesystem.liteRTCacheDirectoryURL
        try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        do {
            try await performOnBridgeQueue {
                try bridgeBox.bridge.prepare(
                    withModelURL: modelURL,
                    cacheDirectoryURL: cacheDirectoryURL,
                    backend: bridgeBackend
                )
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
        lastSystemPrompt = preface.systemPrompt
        lastMemoryContext = memoryContext
        lastMode = mode
    }

    func send(text: String) async throws -> String {
        try await sendStreaming(text: text) { _ in }
    }

    func sendStreaming(text: String, onToken: @escaping @MainActor (String) -> Void) async throws -> String {
        try await sendStreaming(text: text, onToken: onToken, allowCPUFallback: true)
    }

    private func sendStreaming(
        text: String,
        onToken: @escaping @MainActor (String) -> Void,
        allowCPUFallback: Bool
    ) async throws -> String {
        guard prepared else { throw InferenceError.notPrepared }
        var deliveredAnyToken = false
        let bridgeBox = self.bridgeBox

        do {
            let response: String = try await withCheckedThrowingContinuation { continuation in
                let coordinator = InferenceStreamCoordinator(
                    tokenHandler: { token in
                        deliveredAnyToken = true
                        onToken(token)
                    },
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
        } catch {
            if allowCPUFallback, shouldRetryOnCPU(after: error, deliveredAnyToken: deliveredAnyToken) {
                try await recoverConversationForCPUFallback()
                return try await sendStreaming(text: text, onToken: onToken, allowCPUFallback: false)
            }
            throw error
        }
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

    private func shouldRetryOnCPU(after error: Error, deliveredAnyToken: Bool) -> Bool {
        guard deliveredAnyToken == false else { return false }
        guard preparedBackend == .gpu else { return false }
        guard preparedModelURL != nil, lastSystemPrompt != nil, lastMemoryContext != nil, lastMode != nil else { return false }

        if let inferenceError = error as? InferenceError,
           case .streamTimedOut = inferenceError {
            return true
        }

        let nsError = error as NSError
        guard nsError.domain == "LiteRTBridge" else { return false }
        return nsError.code != 499
    }

    private func recoverConversationForCPUFallback() async throws {
        guard let modelURL = preparedModelURL,
              let systemPrompt = lastSystemPrompt,
              let memoryContext = lastMemoryContext,
              let mode = lastMode else {
            throw InferenceError.notPrepared
        }

        try await prepare(modelURL: modelURL, backend: .cpu)

        let bridgeBox = self.bridgeBox
        try await performOnBridgeQueue {
            try bridgeBox.bridge.startConversation(
                withSystemPrompt: systemPrompt,
                memoryContext: memoryContext,
                mode: mode.rawValue
            )
        }
    }
}
