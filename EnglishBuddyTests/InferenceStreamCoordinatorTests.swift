import XCTest
@testable import EnglishBuddyCore

final class InferenceStreamCoordinatorTests: XCTestCase {
    func testCoordinatorFinishesExactlyOnce() async throws {
        let completion = CompletionBox()
        let coordinator = InferenceStreamCoordinator(
            tokenHandler: { _ in },
            completion: { result in
                Task {
                    await completion.store(result)
                }
            },
            onTerminal: {}
        )

        coordinator.receive(token: "Hello ")
        coordinator.finish()
        coordinator.fail(NSError(domain: "Test", code: 1))

        let result = await completion.waitForResult()
        switch result {
        case let .success(text):
            XCTAssertEqual(text, "Hello")
        case let .failure(error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testCoordinatorCancelWinsOverLateFinish() async throws {
        let completion = CompletionBox()
        let coordinator = InferenceStreamCoordinator(
            tokenHandler: { _ in },
            completion: { result in
                Task {
                    await completion.store(result)
                }
            },
            onTerminal: {}
        )

        coordinator.cancel()
        coordinator.finish()

        let result = await completion.waitForResult()
        switch result {
        case .success:
            XCTFail("Expected cancellation")
        case let .failure(error):
            XCTAssertTrue(error is CancellationError)
        }
    }
}

private actor CompletionBox {
    private var storedResult: Result<String, Error>?
    private var waiters: [CheckedContinuation<Result<String, Error>, Never>] = []

    func store(_ result: Result<String, Error>) {
        guard storedResult == nil else { return }
        storedResult = result

        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume(returning: result)
        }
    }

    func waitForResult() async -> Result<String, Error> {
        if let storedResult {
            return storedResult
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
