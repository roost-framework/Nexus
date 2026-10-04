import Testing
@testable import Nexus
import HTTPTypes

@Suite("SSE Tests")
struct SSETests {
    @Test("SSEEvent formats correctly")
    func sseEventFormatting() async throws {
        let event = SSEEvent(
            data: "hello",
            event: "message",
            id: "1",
            retry: 5000
        )

        let formatted = event.formatted()

        #expect(formatted.contains("id: 1"))
        #expect(formatted.contains("event: message"))
        #expect(formatted.contains("retry: 5000"))
        #expect(formatted.contains("data: hello"))
        #expect(formatted.hasSuffix("\n\n"))
    }

    @Test("SSEEvent handles multiline data")
    func multilineData() async throws {
        let event = SSEEvent(
            data: "line1\nline2\nline3"
        )

        let formatted = event.formatted()

        #expect(formatted.contains("data: line1"))
        #expect(formatted.contains("data: line2"))
        #expect(formatted.contains("data: line3"))
    }

    @Test("SSEEvent minimal format")
    func minimalFormat() async throws {
        let event = SSEEvent(data: "test")

        let formatted = event.formatted()

        #expect(formatted == "data: test\n\n")
    }

    @Test("Connection.sseEvent sets correct headers")
    func sseHeaders() async throws {
        let connection = Connection(
            request: HTTPRequest(
                method: .get,
                scheme: "https",
                authority: "example.com",
                path: "/stream"
            )
        )

        let sseConnection = connection.sseEvent { _ in }

        #expect(sseConnection.response.headerFields[.contentType] == "text/event-stream; charset=utf-8")
        #expect(sseConnection.response.headerFields[.cacheControl] == "no-cache, no-transform")
        let bufferingHeader = try #require(HTTPField.Name("X-Accel-Buffering"))
        #expect(sseConnection.response.headerFields[bufferingHeader] == "no")
    }
}
