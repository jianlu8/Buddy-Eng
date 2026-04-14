import Foundation

private enum StreamCoordinatorError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        "The local model stopped responding before finishing the reply."
    }
}

final class InferenceStreamCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let timeoutNanoseconds: UInt64
    private let tokenHandler: @MainActor (String) -> Void
    private let completion: @Sendable (Result<String, Error>) -> Void
    private let onTerminal: @Sendable () -> Void

    private var collected = ""
    private var finished = false
    private var lastActivity = Date()
    private var watchdogTask: Task<Void, Never>?

    init(
        timeoutNanoseconds: UInt64 = 25_000_000_000,
        tokenHandler: @escaping @MainActor (String) -> Void,
        completion: @escaping @Sendable (Result<String, Error>) -> Void,
        onTerminal: @escaping @Sendable () -> Void
    ) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.tokenHandler = tokenHandler
        self.completion = completion
        self.onTerminal = onTerminal
    }

    deinit {
        watchdogTask?.cancel()
    }

    func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task.detached { [weak self] in
            while let self, Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let shouldTimeout: Bool = self.lock.withLock {
                    guard self.finished == false else { return false }
                    return Date().timeIntervalSince(self.lastActivity) >= 25
                }
                if shouldTimeout {
                    self.fail(StreamCoordinatorError.timedOut)
                    return
                }
            }
        }
    }

    func receive(token: String) {
        let trimmed = token.isEmpty == false
        let tokenToDeliver = lock.withLock { () -> String? in
            guard finished == false else { return nil }
            lastActivity = Date()
            collected += token
            return trimmed ? token : nil
        }
        guard let tokenToDeliver else { return }
        Task { @MainActor in
            tokenHandler(tokenToDeliver)
        }
    }

    func finish() {
        let result: String? = lock.withLock {
            guard finished == false else { return nil }
            finished = true
            return collected.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let result else { return }
        watchdogTask?.cancel()
        completion(.success(result))
        onTerminal()
    }

    func fail(_ error: Error) {
        let shouldComplete = lock.withLock {
            guard finished == false else { return false }
            finished = true
            return true
        }
        guard shouldComplete else { return }
        watchdogTask?.cancel()
        completion(.failure(error))
        onTerminal()
    }

    func cancel() {
        fail(CancellationError())
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
