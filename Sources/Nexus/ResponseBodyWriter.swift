import Foundation

/// The transport sink for a producer-backed response body.
///
/// Each write suspends until the transport accepts the chunk. Produce chunks
/// sequentially, awaiting each write before creating the next one. Nexus adds
/// no intermediate queue; the transport and operating system may buffer bytes.
/// The writer belongs to the response task and must not escape the producer.
/// Return from the producer to finish, or throw to terminate with an error.
public protocol ResponseBodyWriter {
    /// Writes one chunk, respecting transport backpressure.
    ///
    /// - Parameter data: The bytes to send.
    /// - Throws: Cancellation or a transport write failure.
    mutating func write(_ data: Data) async throws
}

extension ResponseBodyWriter {
    /// Writes a UTF-8 string, respecting transport backpressure.
    ///
    /// - Parameter string: The text to send.
    /// - Throws: Cancellation or a transport write failure.
    public mutating func write(_ string: String) async throws {
        try await write(Data(string.utf8))
    }

    /// Writes a formatted Server-Sent Event.
    ///
    /// - Parameter event: The event to encode and send.
    /// - Throws: Cancellation or a transport write failure.
    public mutating func write(_ event: SSEEvent) async throws {
        try await write(event.formatted())
    }
}
