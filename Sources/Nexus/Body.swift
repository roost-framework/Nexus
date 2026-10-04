import Foundation

/// Represents the body of an HTTP request.
///
/// Use `.empty` when there is no body, `.buffered` when the full body is
/// available as a `Data` value, and `.stream` when the body is delivered
/// incrementally as an async sequence of `Data` chunks.
public enum RequestBody: Sendable {
    /// No request body.
    case empty

    /// A fully buffered request body.
    case buffered(Data)

    /// A streaming request body delivered as successive `Data` chunks.
    case stream(AsyncThrowingStream<Data, any Error>)
}

/// Represents the body of an HTTP response.
///
/// Use `.empty` when there is no body, `.buffered` when the full body is
/// available as a `Data` value, `.stream` to consume an existing sequence,
/// and `.producer` to write chunks with transport backpressure.
public enum ResponseBody: Sendable {
    /// No response body.
    case empty

    /// A fully buffered response body.
    case buffered(Data)

    /// A streaming response body produced as successive `Data` chunks.
    ///
    /// Buffering and producer cancellation are owned by the supplied stream.
    /// Prefer ``producer(_:)`` for producers that need transport backpressure.
    case stream(AsyncThrowingStream<Data, any Error>)

    /// A lazy producer executed by the adapter while sending the response.
    ///
    /// Await each write before producing the next chunk. Returning finishes
    /// the response; throwing aborts it. The producer is never started for a
    /// suppressed body (such as HEAD or 204), and Nexus creates no extra task
    /// or queue. Cancellation is cooperative; write failures propagate to the
    /// producer. Disconnect detection depends on the transport and may require
    /// a write, so idle SSE producers should send periodic heartbeat events.
    case producer(@Sendable (inout any ResponseBodyWriter) async throws -> Void)
}

// MARK: - Convenience

extension ResponseBody {

    /// Creates a `.buffered` response body from a UTF-8 encoded string.
    ///
    /// - Parameter string: The string to encode.
    /// - Returns: A `.buffered` body, or `.empty` if the string cannot be encoded.
    public static func string(_ string: String) -> ResponseBody {
        guard let data = string.data(using: .utf8) else { return .empty }
        return .buffered(data)
    }
}
