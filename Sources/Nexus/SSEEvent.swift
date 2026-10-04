/// Formats a Server-Sent Event string per the SSE specification.
///
/// Each field appears on its own line. Multi-line `data` is split into
/// multiple `data:` lines. The event is terminated by a blank line (`\n\n`).
///
/// ```swift
/// try await writer.write(sseEvent(data: "hello", event: "message"))
/// // Output: "event: message\ndata: hello\n\n"
/// ```
///
/// - Parameters:
///   - data: The event data. Multi-line data is split across `data:` lines.
///   - event: The event type. Optional.
///   - id: The event ID. Optional.
///   - retry: Reconnection time in milliseconds. Optional.
/// - Returns: A formatted SSE event string ending with a blank line.
public func sseEvent(
    data: String,
    event: String? = nil,
    id: String? = nil,
    retry: Int? = nil
) -> String {
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
