import Foundation
import HTTPTypes
import Nexus
import NexusVapor
import Testing
import Vapor

@Suite("Vapor transport regressions")
struct TransportRegressionTests {
    @Test func test_vapor_requestTargetAndRepeatedHeaders_reachPipeline() async throws {
        try await withApplication { app in
            let adapter = NexusVaporAdapter(plug: { conn in
                #expect(conn.scheme == "https")
                #expect(conn.host == "::1")
                #expect(conn.port == 8443)
                #expect(conn.request.path == "/search?q=hello%20world&tag=a&tag=b")
                #expect(conn.queryParameters["tag"] == ["a", "b"])
                #expect(conn.getReqHeaders(.accept) == ["text/html", "application/json"])
                #expect(conn.reqCookies == ["a": "1", "b": "2"])
                return conn.respond(status: .ok)
            })
            var headers = HTTPHeaders()
            headers.add(name: "Accept", value: "text/html")
            headers.add(name: "Accept", value: "application/json")
            headers.add(name: "Cookie", value: "a=1")
            headers.add(name: "Cookie", value: "b=2")
            let request = Request(
                application: app, method: .GET,
                url: URI(string: "https://[::1]:8443/search?q=hello%20world&tag=a&tag=b"),
                headers: headers, collectedBody: ByteBuffer(), on: app.eventLoopGroup.next()
            )
            let response = try await adapter.respond(to: request, chainingTo: UnusedResponder())
            #expect(response.status == .ok)
        }
    }

    @Test(arguments: ["empty", "buffered", "stream", "producer"])
    func test_vapor_multipleCookies_surviveEveryBodyType(_ kind: String) async throws {
        try await withApplication { app in
            let adapter = NexusVaporAdapter(plug: { conn in
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
                    .putRespCookie(Nexus.Cookie(name: "a", value: "1"))
                    .registerBeforeSend { $0.putRespCookie(Nexus.Cookie(name: "b", value: "2")) }
            })
            let request = Request(application: app, method: .GET, url: "/", on: app.eventLoopGroup.next())
            let response = try await adapter.respond(to: request, chainingTo: UnusedResponder())
            #expect(response.headers["set-cookie"] == ["a=1", "b=2"])
            let body = try await response.body.collect(on: app.eventLoopGroup.next()).get()
            #expect(body.map { String(buffer: $0) } ?? "" == (kind == "empty" ? "" : "hello"))
        }
    }

    @Test func test_vapor_precollectedBodyLimit_rejectsBeforePipeline() async throws {
        try await withApplication { app in
            let adapter = NexusVaporAdapter(
                plug: { conn in
                    Issue.record("Oversize requests must not reach the pipeline")
                    return conn
                }, maxRequestBodySize: 2)
            let request = Request(
                application: app, method: .POST, url: "/", collectedBody: ByteBuffer(string: "abc"),
                on: app.eventLoopGroup.next()
            )
            do {
                _ = try await adapter.respond(to: request, chainingTo: UnusedResponder())
                Issue.record("Expected a payload limit error")
            } catch let error as AbortError {
                #expect(error.status == .payloadTooLarge)
            }
        }
    }

    @Test func test_vapor_faviconHeadAndConditional_preserveRepresentationMetadata() async throws {
        try await withApplication { app in
            let adapter = NexusVaporAdapter(plug: Favicon(iconData: Data([0, 1, 2, 3])).asPlug())
            let request = Request(application: app, method: .GET, url: "/favicon.ico", on: app.eventLoopGroup.next())
            let get = try await adapter.respond(to: request, chainingTo: UnusedResponder())
            let tag = try #require(get.headers.first(name: .eTag))
            let headRequest = Request(
                application: app, method: .HEAD, url: "/favicon.ico", on: app.eventLoopGroup.next())
            let head = try await adapter.respond(to: headRequest, chainingTo: UnusedResponder())
            #expect(head.body.count == 0)
            #expect(head.headers.first(name: .contentLength) == "4")
            #expect(head.headers.first(name: .eTag) == tag)
            request.headers.replaceOrAdd(name: .ifNoneMatch, value: "W/" + tag)
            let conditional = try await adapter.respond(to: request, chainingTo: UnusedResponder())
            #expect(conditional.status == .notModified)
            #expect(conditional.body.count == 0)
            #expect(conditional.headers.first(name: .eTag) == tag)
            #expect(conditional.headers.first(name: .contentLength) == nil)
        }
    }

    @Test func test_vapor_streamFailure_reachesConsumer() async throws {
        struct StreamFailure: Error {}
        try await withApplication { app in
            let adapter = NexusVaporAdapter(plug: { conn in
                let stream = AsyncThrowingStream<Data, Error> { continuation in
                    continuation.yield(Data("partial".utf8))
                    continuation.finish(throwing: StreamFailure())
                }
                return conn.respond(status: .ok, body: .stream(stream))
            })
            let request = Request(application: app, method: .GET, url: "/", on: app.eventLoopGroup.next())
            let response = try await adapter.respond(to: request, chainingTo: UnusedResponder())
            await #expect(throws: StreamFailure.self) {
                try await response.body.collect(on: app.eventLoopGroup.next()).get()
            }
        }
    }

    @Test(arguments: [200, 204, 205, 304])
    func test_vapor_headAndBodylessStatus_suppressBody(_ code: Int) async throws {
        try await withApplication { app in
            let adapter = NexusVaporAdapter(plug: { $0.respond(status: .init(code: code), body: .string("hello")) })
            let request = Request(
                application: app, method: code == 200 ? .HEAD : .GET, url: "/", on: app.eventLoopGroup.next()
            )
            let response = try await adapter.respond(to: request, chainingTo: UnusedResponder())
            #expect(response.status.code == UInt(code))
            #expect(response.body.count == 0)
            let expectedLength: String? = code == 200 ? "5" : (code == 205 ? "0" : nil)
            #expect(response.headers.first(name: .contentLength) == expectedLength)
        }
    }
}

private struct UnusedResponder: AsyncResponder {
    func respond(to request: Request) async throws -> Response {
        Issue.record("The Nexus adapter is terminal")
        return Response(status: .internalServerError)
    }
}

private func withApplication(_ test: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    do {
        try await test(app)
    } catch {
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
