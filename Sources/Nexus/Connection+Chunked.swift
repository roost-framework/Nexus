import HTTPTypes

extension Connection {
    /// The writer passed to a chunked response producer.
    public typealias ChunkWriter = ResponseBodyWriter

    /// Returns a halted connection with a lazy streaming response body.
    ///
    /// The adapter runs `handler` when sending the response. Await every write
    /// to respect transport backpressure. Returning finishes the response;
    /// throwing aborts it. Use `defer` for producer resources and allow write
    /// failures and cancellation to propagate. Do not spawn a separate task.
    ///
    /// ```swift
    /// conn.sendChunked { writer in
    ///     try await writer.write("hello")
    ///     try await writer.write("world")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - status: The HTTP response status. Defaults to `.ok`.
    ///   - handler: The producer, scoped to response delivery.
    /// - Returns: A halted connection with a producer-backed response body.
    public func sendChunked(
        status: HTTPResponse.Status = .ok,
        handler: @escaping @Sendable (inout any ChunkWriter) async throws -> Void
    ) -> Connection {
        var copy = self
        copy.response.status = status
        copy.responseBody = .producer(handler)
        copy.isHalted = true
        return copy
    }
}
