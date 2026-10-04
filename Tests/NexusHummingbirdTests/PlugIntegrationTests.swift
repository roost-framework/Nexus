import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Nexus
import NexusHummingbird
import Testing

/// Integration tests verifying plug behaviour through the real Hummingbird adapter.
///
/// Each test runs through the full request/response cycle:
/// NexusHummingbirdAdapter → Nexus plug pipeline → back through adapter.
/// Uses Hummingbird's `.router` test mode (no live network).
@Suite("Plug Integration Tests")
struct PlugIntegrationTests {

    private func withApp(
        plug: @escaping Plug,
        _ test: @Sendable (any TestClientProtocol) async throws -> Void
    ) async throws {
        let adapter = NexusHummingbirdAdapter(plug: plug)
        let app = Application(responder: adapter)
        try await app.test(.router) { client in
            try await test(client)
        }
    }

    // MARK: - Compression Integration

    @Test("Compression: gzip header survives Hummingbird adapter round-trip")
    func compressionGzipHeader() async throws {
        let largePlug: Plug = { conn in
            let body = Data(String(repeating: "x", count: 2048).utf8)
            return conn.respond(status: .ok, body: .buffered(body))
        }
        let plug = pipe(Compression().asPlug(), largePlug)

        try await withApp(plug: plug) { client in
            let response = try await client.execute(
                uri: "/",
                method: .get,
                headers: [.acceptEncoding: "gzip"]
            )
            #expect(response.status == .ok)
            let encoding = response.headers[values: .contentEncoding].first
            #expect(encoding == "gzip")
        }
    }

    @Test("Compression: streaming body passes through adapter without compression")
    func compressionStreamingPassthrough() async throws {
        let streamPlug: Plug = { conn in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                continuation.yield(Data("hello".utf8))
                continuation.finish()
            }
            return conn.respond(status: .ok, body: .stream(stream))
        }
        let plug = pipe(Compression().asPlug(), streamPlug)

        try await withApp(plug: plug) { client in
            let response = try await client.execute(
                uri: "/",
                method: .get,
                headers: [.acceptEncoding: "gzip"]
            )
            #expect(response.status == .ok)
            let encoding = response.headers[values: .contentEncoding].first
            #expect(encoding == nil)
        }
    }

    @Test("Compression: Content-Length reflects compressed bytes")
    func compressionContentLengthAbsent() async throws {
        let body = Data(String(repeating: "a", count: 2048).utf8)
        let largePlug: Plug = { conn in
            var result = conn.respond(status: .ok, body: .buffered(body))
            result.response.headerFields[.contentLength] = "\(body.count)"
            return result
        }
        let plug = pipe(Compression().asPlug(), largePlug)

        try await withApp(plug: plug) { client in
            let response = try await client.execute(
                uri: "/",
                method: .get,
                headers: [.acceptEncoding: "gzip"]
            )
            #expect(response.status == .ok)
            #expect(response.headers[.contentEncoding] == "gzip")
            #expect(response.headers[.contentLength] == String(response.body.readableBytes))
            #expect(response.body.readableBytes < body.count)
        }
    }

    // MARK: - ContentNegotiation Integration

    @Test("ContentNegotiation: 406 exits pipeline and is returned correctly")
    func contentNegotiation406() async throws {
        let plug = pipe(
            ContentNegotiation(supported: ["application/json"]).asPlug(),
            { conn in conn.respond(status: .ok, body: .string("ok")) }
        )

        try await withApp(plug: plug) { client in
            let response = try await client.execute(
                uri: "/",
                method: .get,
                headers: [.accept: "text/xml"]
            )
            #expect(response.status == .notAcceptable)
        }
    }

    @Test("ContentNegotiation: negotiated type is accessible downstream in pipeline")
    func contentNegotiationDownstreamAccess() async throws {
        let handler: Plug = { conn in
            let mime = conn[ContentNegotiation.NegotiatedTypeKey.self] ?? "none"
            return conn.respond(status: .ok, body: .string(mime))
        }
        let plug = pipe(
            ContentNegotiation(supported: ["application/json", "text/html"]).asPlug(),
            handler
        )

        try await withApp(plug: plug) { client in
            let response = try await client.execute(
                uri: "/",
                method: .get,
                headers: [.accept: "text/html"]
            )
            #expect(response.status == .ok)
            let body = String(buffer: response.body)
            #expect(body == "text/html")
        }
    }

    @Test("ContentNegotiation: missing Accept uses first supported type")
    func contentNegotiationNoHeader() async throws {
        let handler: Plug = { conn in
            let mime = conn[ContentNegotiation.NegotiatedTypeKey.self] ?? "none"
            return conn.respond(status: .ok, body: .string(mime))
        }
        let plug = pipe(
            ContentNegotiation(supported: ["application/json"]).asPlug(),
            handler
        )

        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/", method: .get)
            let body = String(buffer: response.body)
            #expect(body == "application/json")
        }
    }

    // MARK: - Timeout Integration

    @Test("Timeout: fast plug completes normally through adapter")
    func timeoutFastPlug() async throws {
        let timeout = Timeout(seconds: 5)
        let plug = timeout.wrap { conn in conn.respond(status: .ok, body: .string("fast")) }

        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.status == .ok)
        }
    }

    @Test("Timeout: timeout error is handled by onError wrapper in adapter")
    func timeoutErrorHandled() async throws {
        let timeout = Timeout(nanoseconds: 1_000_000)  // 1ms
        let slowPlug: Plug = { conn in
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            return conn.respond(status: .ok)
        }
        let plug = onError(timeout.wrap(slowPlug)) { conn, error in
            if error is Timeout.TimeoutError {
                return conn.respond(status: .serviceUnavailable, body: .string("timed out"))
            }
            return conn.respond(status: .internalServerError)
        }

        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.status == .serviceUnavailable)
        }
    }

    @Test("Timeout: response body preserved when within timeout")
    func timeoutResponseBodyPreserved() async throws {
        let timeout = Timeout(seconds: 5)
        let plug = timeout.wrap { conn in
            conn.respond(status: .ok, body: .string("body content"))
        }

        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/", method: .get)
            let body = String(buffer: response.body)
            #expect(body == "body content")
        }
    }

    // MARK: - Favicon Integration

    @Test("Favicon: /favicon.ico is served through adapter")
    func faviconServed() async throws {
        let iconBytes = Data([0x00, 0x00, 0x01, 0x00])
        let plug = pipe(
            Favicon(iconData: iconBytes).asPlug(),
            { conn in conn.respond(status: .notFound) }
        )

        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/favicon.ico", method: .get)
            #expect(response.status == .ok)
        }
    }

    @Test("Favicon: Content-Type header survives adapter serialization")
    func faviconContentType() async throws {
        let iconBytes = Data([0x00, 0x00, 0x01, 0x00])
        let plug = Favicon(iconData: iconBytes).asPlug()

        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/favicon.ico", method: .get)
            let contentType = response.headers[values: .contentType].first
            #expect(contentType == "image/x-icon")
        }
    }

    @Test("Favicon: non-favicon path falls through to next plug")
    func faviconPassthrough() async throws {
        let iconBytes = Data([0x00, 0x00, 0x01, 0x00])
        let plug = pipe(
            Favicon(iconData: iconBytes).asPlug(),
            { conn in conn.respond(status: .ok, body: .string("from router")) }
        )

        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/api/users", method: .get)
            #expect(response.status == .ok)
            #expect(String(buffer: response.body) == "from router")
        }
    }

    @Test("Favicon: icon body bytes match configured data after adapter round-trip")
    func faviconBodyBytes() async throws {
        let iconBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let plug = Favicon(iconData: iconBytes).asPlug()

        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/favicon.ico", method: .get)
            let received = Data(response.body.readableBytesView)
            #expect(received == iconBytes)
        }
    }

    @Test func test_favicon_headAndConditional_preserveRepresentationMetadata() async throws {
        let plug = Favicon(iconData: Data([0, 1, 2, 3])).asPlug()
        try await withApp(plug: plug) { client in
            let get = try await client.execute(uri: "/favicon.ico", method: .get)
            let tag = try #require(get.headers[.eTag])
            let head = try await client.execute(uri: "/favicon.ico", method: .head)
            #expect(head.body.readableBytes == 0)
            #expect(head.headers[.contentLength] == "4")
            #expect(head.headers[.eTag] == tag)
            let conditional = try await client.execute(
                uri: "/favicon.ico", method: .get, headers: [.ifNoneMatch: "W/" + tag]
            )
            #expect(conditional.status == .notModified)
            #expect(conditional.body.readableBytes == 0)
            #expect(conditional.headers[.eTag] == tag)
            #expect(conditional.headers[.contentLength] == nil)
        }
    }
}
