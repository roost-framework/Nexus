import Foundation

// MARK: - Timeout

/// Applies a time limit to a plug or pipeline.
///
/// If the wrapped plug does not complete within the configured duration, the
/// task is cancelled and ``TimeoutError`` is thrown. Combine with ``onError(_:handler:)``
/// to return a friendly response:
///
/// ```swift
/// let timeout = Timeout(seconds: 30)
/// let timedApp = onError(timeout.wrap(router)) { conn, error in
///     if error is Timeout.TimeoutError {
///         return conn.respond(status: .serviceUnavailable, body: .string("Request timed out"))
///     }
///     return conn.respond(status: .internalServerError, body: .string("Server error"))
/// }
/// ```
public struct Timeout: Sendable {

    /// Thrown when a plug exceeds the configured time limit.
    public struct TimeoutError: Error, Sendable {}

    private let nanoseconds: UInt64

    /// Creates a `Timeout` with the given duration in nanoseconds.
    ///
    /// - Parameter nanoseconds: Maximum allowed execution time in nanoseconds.
    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    /// Creates a `Timeout` with the given duration in seconds.
    ///
    /// - Parameter seconds: Maximum allowed execution time in seconds. Nonpositive
    ///   values and NaN expire immediately; values beyond UInt64 nanoseconds saturate.
    public init(seconds: Double) {
        if seconds.isNaN || seconds <= 0 {
            self.nanoseconds = 0
        } else if seconds >= Double(UInt64.max) / 1_000_000_000 {
            self.nanoseconds = .max
        } else {
            self.nanoseconds = UInt64(seconds * 1_000_000_000)
        }
    }

    /// Returns a plug that runs `plug` subject to this timeout.
    ///
    /// The wrapped plug and a sleep task race. Whichever finishes first wins:
    /// - If `plug` finishes first, its result is returned and the sleep is cancelled.
    /// - If the sleep finishes first, ``TimeoutError`` is thrown and `plug` is cancelled.
    /// Cancellation is cooperative: structured concurrency waits for the plug to
    /// exit. Blocking work that ignores cancellation can delay the timeout error.
    ///
    /// - Parameter plug: The plug or pipeline to wrap.
    /// - Returns: A new plug that throws ``TimeoutError`` on timeout.
    public func wrap(_ plug: @escaping Plug) -> Plug {
        let ns = nanoseconds
        return { conn in
            guard !conn.isHalted else { return conn }
            try Task.checkCancellation()
            guard ns > 0 else { throw TimeoutError() }
            return try await withThrowingTaskGroup(of: Connection.self) { group in
                defer { group.cancelAll() }
                group.addTask {
                    try await plug(conn)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: ns)
                    throw TimeoutError()
                }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
        }
    }
}
