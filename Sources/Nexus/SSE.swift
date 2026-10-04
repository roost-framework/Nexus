import Foundation
import HTTPTypes

// MARK: - SSE Event Model

/// A single Server-Sent Event with optional fields.
///
/// SSE events consist of a required `data` field and optional `event`, `id`,
/// and `retry` fields. This model captures those values for formatting by
/// ``sseEvent(data:event:id:retry:)``.
public struct SSEEvent: Sendable {
    /// The event data. Multi-line data is split across multiple `data:` lines.
    public var data: String

    /// The event type (e.g., `"message"`, `"update"`). Optional.
    public var event: String?

    /// A unique identifier for this event. Optional.
    public var id: String?

    /// The reconnection time in milliseconds. Optional.
    public var retry: Int?

    /// Creates a new SSE event.
    ///
    /// - Parameters:
    ///   - data: The event data. Multi-line data is split across `data:` lines.
    ///   - event: The event type. Optional.
    ///   - id: A unique identifier for this event. Optional.
    ///   - retry: Reconnection time in milliseconds. Optional.
    @inlinable
    public init(
        data: String,
        event: String? = nil,
        id: String? = nil,
        retry: Int? = nil
    ) {
        self.data = data
        self.event = event
        self.id = id
        self.retry = retry
    }

    /// Formats this event as an SSE string per the specification.
    ///
    /// Each field appears on its own line. Multi-line `data` is split into
    /// multiple `data:` lines. The event is terminated by a blank line (`\n\n`).
    ///
    /// - Returns: A formatted SSE event string ending with a blank line.
    @inlinable
    public func formatted() -> String {
        var lines: [String] = []
        if let id {
            lines.append("id: \(id)")
        }
        if let event {
            lines.append("event: \(event)")
        }
        if let retry {
            lines.append("retry: \(retry)")
        }
        for line in data.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append("data: \(line)")
        }
        return lines.joined(separator: "\n") + "\n\n"
    }
}

// MARK: - Connection Extension

extension Connection {
    /// Returns a halted connection that produces Server-Sent Events.
    ///
    /// The adapter runs `body` while delivering the response. Await each write;
    /// returning finishes the stream and throwing aborts it. For idle streams,
    /// send periodic heartbeat comments (`": heartbeat\n\n"`) so a failed
    /// transport write can detect a disconnected client. Do not spawn a task.
    ///
    /// ```swift
    /// connection.sseEvent { writer in
    ///     try await writer.write(SSEEvent(data: "hello", event: "message"))
    ///     try await Task.sleep(for: .seconds(1))
    ///     try await writer.write(SSEEvent(data: "world", event: "message"))
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - contentType: The event stream media type and charset.
    ///   - body: An async producer that writes events, text, or raw data.
    /// - Returns: A halted connection with caching and proxy buffering disabled.
    public func sseEvent(
        contentType: String = "text/event-stream; charset=utf-8",
        body: @escaping @Sendable (inout any ChunkWriter) async throws -> Void
    ) -> Connection {
        var copy = putRespContentType(contentType)
        copy.response.headerFields[.cacheControl] = "no-cache, no-transform"
        if let name = HTTPField.Name("X-Accel-Buffering") {
            copy.response.headerFields[name] = "no"
        }
        return copy.sendChunked(handler: body)
    }
}
