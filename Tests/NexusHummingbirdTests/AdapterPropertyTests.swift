import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Nexus
import NexusHummingbird
import Testing

/// Parameterized transport checks through the real adapter and Hummingbird's router test client.
@Suite("Hummingbird adapter properties")
struct AdapterPropertyTests {
    private func withApp(
        plug: @escaping Plug,
        test: @Sendable (any TestClientProtocol) async throws -> Void
    ) async throws {
        let app = Application(responder: NexusHummingbirdAdapter(plug: plug))
        try await app.test(.router, test)
    }

    @Test(arguments: [200, 201, 202, 204, 301, 302, 304, 400, 401, 403, 404, 422, 500, 502, 503])
    func test_adapter_responseStatus_preservesCode(_ code: Int) async throws {
        try await withApp {
            $0.respond(status: .init(code: code))
        } test: { client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.status.code == code)
        }
    }

    @Test(arguments: [0, 10, 100, 512, 1024])
    func test_adapter_bufferedResponse_preservesBytes(_ size: Int) async throws {
        let bytes = Data((0..<size).map { UInt8(truncatingIfNeeded: $0) })
        try await withApp {
            $0.respond(status: .ok, body: .buffered(bytes))
        } test: { client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(Data(response.body.readableBytesView) == bytes)
            #expect(response.headers[.contentLength] == String(size))
        }
    }

    @Test(arguments: [HTTPRequest.Method.get, .post, .put, .delete, .patch])
    func test_adapter_requestMetadata_reachesPipeline(_ method: HTTPRequest.Method) async throws {
        try await withApp { conn in
            #expect(conn.request.method == method)
            #expect(conn.request.path == "/search?tag=a&tag=b")
            #expect(conn.queryParameters["tag"] == ["a", "b"])
            #expect(conn.getReqHeaders(.accept) == ["text/html", "application/json"])
            #expect(conn.reqCookies == ["a": "1", "b": "2"])
            return conn.respond(status: .ok)
        } test: { client in
            let headers = HTTPFields([
                HTTPField(name: .accept, value: "text/html"),
                HTTPField(name: .accept, value: "application/json"),
                HTTPField(name: .cookie, value: "a=1"),
                HTTPField(name: .cookie, value: "b=2"),
            ])
            let response = try await client.execute(uri: "/search?tag=a&tag=b", method: method, headers: headers)
            #expect(response.status == .ok)
        }
    }

    @Test(arguments: ["empty", "buffered", "stream", "producer"])
    func test_adapter_repeatedCookies_surviveEveryBodyType(_ kind: String) async throws {
        try await withApp { conn in
            let body: Nexus.ResponseBody
            switch kind {
            case "buffered": body = .string("hello")
            case "producer": body = .producer { try await $0.write("hello") }
            case "stream":
                body = .stream(
                    AsyncThrowingStream { continuation in
                        continuation.yield(Data("hello".utf8))
                        continuation.finish()
                    })
            default: body = .empty
            }
            return conn.respond(status: .ok, body: body)
                .putRespCookie(Cookie(name: "a", value: "1"))
                .registerBeforeSend { $0.putRespCookie(Cookie(name: "b", value: "2")) }
        } test: { client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.headers[values: .setCookie] == ["a=1", "b=2"])
            #expect(String(buffer: response.body) == (kind == "empty" ? "" : "hello"))
        }
    }

    @Test func test_adapter_haltedPipeline_preservesRejection() async throws {
        let plug = pipeline([
            { $0.respond(status: .forbidden, body: .string("access denied")) },
            { conn in
                Issue.record("A halted pipeline must skip downstream plugs")
                return conn
            },
        ])
        try await withApp(plug: plug) { client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.status == .forbidden)
            #expect(String(buffer: response.body) == "access denied")
        }
    }

    @Test func test_adapter_thrownError_returns500() async throws {
        struct InfrastructureError: Error {}
        try await withApp { _ in
            throw InfrastructureError()
        } test: { client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.status == .internalServerError)
        }
    }

    @Test func test_adapter_beforeSendHooks_executeOnceInLIFOOrder() async throws {
        try await withApp { conn in
            var result = conn
            for index in 0..<5 {
                result = result.registerBeforeSend { conn in
                    let order = conn.getRespHeader("X-Hook-Order") ?? ""
                    return conn.putRespHeader("X-Hook-Order", order + String(index))
                }
            }
            return result.respond(status: .ok)
        } test: { client in
            let response = try await client.execute(uri: "/", method: .get)
            let name = try #require(HTTPField.Name("X-Hook-Order"))
            #expect(response.headers[name] == "43210")
        }
    }

    @Test func test_adapter_headResponse_suppressesBodyAndPreservesLength() async throws {
        try await withApp {
            $0.respond(status: .ok, body: .string("hello"))
        } test: { client in
            let response = try await client.execute(uri: "/", method: .head)
            #expect(response.body.readableBytes == 0)
            #expect(response.headers[.contentLength] == "5")
        }
    }

    @Test(arguments: [204, 205, 304])
    func test_adapter_bodylessStatus_suppressesBody(_ code: Int) async throws {
        try await withApp {
            $0.respond(status: .init(code: code), body: .string("must not be sent"))
        } test: {
            client in
            let response = try await client.execute(uri: "/", method: .get)
            #expect(response.status.code == code)
            #expect(response.body.readableBytes == 0)
            #expect(response.headers[.contentLength] == (code == 205 ? "0" : nil))
        }
    }
}
