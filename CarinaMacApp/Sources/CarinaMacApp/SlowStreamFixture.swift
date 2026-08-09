#if DEBUG
import Foundation

/// A deterministic, local-only stream for exercising cancellation in debug builds.
struct SlowStreamFixture {
    static func generate(
        tokenCount: Int = 200,
        interval: TimeInterval = 0.1
    ) -> AsyncThrowingStream<String, Error> {
        precondition(tokenCount >= 0, "tokenCount must be non-negative")
        precondition(interval > 0, "interval must be positive")

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for index in 0 ..< tokenCount {
                        try Task.checkCancellation()
                        try await Task.sleep(
                            nanoseconds: UInt64(interval * 1_000_000_000)
                        )
                        continuation.yield("token\(index) ")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
