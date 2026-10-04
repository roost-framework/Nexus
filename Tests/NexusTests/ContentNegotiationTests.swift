import HTTPTypes
import Testing

@testable import Nexus
@testable import NexusTest

@Suite("ContentNegotiation Plug")
struct ContentNegotiationParityTests {

    private func negotiate(
        _ conn: Connection,
        supported: [String] = ["application/json", "text/html"]
    ) async throws -> Connection {
        try await ContentNegotiation(supported: supported).call(conn)
    }

    private func makeConn(accept: String) -> Connection {
        Connection.make(headers: HTTPFields([HTTPField(name: .accept, value: accept)]))
    }

    // MARK: - Exact Match

    @Test("exact MIME type match stores negotiated type")
    func exactMatch() async throws {
        let conn = makeConn(accept: "application/json")
        let result = try await negotiate(conn)
        let negotiated = result[ContentNegotiation.NegotiatedTypeKey.self]
        #expect(negotiated == "application/json")
        #expect(!result.isHalted)
    }

    @Test("second supported type matched when first not accepted")
    func secondTypeMatched() async throws {
        let conn = makeConn(accept: "text/html")
        let result = try await negotiate(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "text/html")
    }

    // MARK: - Quality Values

    @Test("higher quality value wins over lower")
    func qualityOrdering() async throws {
        let conn = makeConn(accept: "text/html;q=0.9, application/json;q=1.0")
        let result = try await negotiate(conn, supported: ["text/html", "application/json"])
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "application/json")
    }

    @Test("q=0 means client rejects that type")
    func qualityZeroRejected() async throws {
        let conn = makeConn(accept: "application/json;q=0, text/html")
        let result = try await negotiate(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "text/html")
    }

    @Test("implicit q=1.0 beats explicit q=0.8")
    func implicitQuality() async throws {
        let conn = makeConn(accept: "text/html, application/json;q=0.8")
        let result = try await negotiate(conn, supported: ["application/json", "text/html"])
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "text/html")
    }

    // MARK: - Wildcard

    @Test("wildcard */* matches first supported type")
    func wildcardMatchesFirst() async throws {
        let conn = makeConn(accept: "*/*")
        let result = try await negotiate(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "application/json")
    }

    @Test("subtype wildcard application/* matches application/json")
    func subtypeWildcard() async throws {
        let conn = makeConn(accept: "application/*")
        let result = try await negotiate(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "application/json")
    }

    // MARK: - Missing Accept Header

    @Test("missing Accept header uses first supported type")
    func missingAcceptUsesFirst() async throws {
        let conn = Connection.make()
        let result = try await negotiate(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "application/json")
    }

    @Test("missing Accept with custom defaultType uses defaultType")
    func missingAcceptUsesDefault() async throws {
        let conn = Connection.make()
        let plug = ContentNegotiation(supported: ["application/json", "text/html"], defaultType: "text/html")
        let result = try await plug.call(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "text/html")
    }

    // MARK: - 406 Not Acceptable

    @Test("no overlap returns 406")
    func noOverlapReturns406() async throws {
        let conn = makeConn(accept: "text/xml")
        let result = try await negotiate(conn)
        #expect(result.response.status == .notAcceptable)
        #expect(result.isHalted)
    }

    @Test("406 body lists supported types")
    func notAcceptableBody() async throws {
        let conn = makeConn(accept: "text/xml")
        let result = try await negotiate(conn, supported: ["application/json"])
        guard case .buffered(let data) = result.responseBody else {
            Issue.record("Expected .buffered body")
            return
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("application/json"))
    }

    @Test("all q=0 returns 406")
    func allQZeroReturns406() async throws {
        let conn = makeConn(accept: "application/json;q=0, text/html;q=0")
        let result = try await negotiate(conn)
        #expect(result.response.status == .notAcceptable)
    }

    // MARK: - Case Insensitivity

    @Test("MIME type matching is case-insensitive")
    func caseInsensitive() async throws {
        let conn = makeConn(accept: "Application/JSON")
        let result = try await negotiate(conn)
        let negotiated = result[ContentNegotiation.NegotiatedTypeKey.self]
        #expect(negotiated != nil)
        #expect(!result.isHalted)
    }

    // MARK: - Downstream Access

    @Test("negotiated type is readable downstream via assign key")
    func negotiatedTypeAccessibleDownstream() async throws {
        let conn = makeConn(accept: "text/html")
        let registered = try await negotiate(conn)
        // A downstream plug can read the negotiated type
        let mime = registered[ContentNegotiation.NegotiatedTypeKey.self]
        #expect(mime == "text/html")
    }

    @Test("pipeline: ContentNegotiation followed by handler reads negotiated type")
    func pipelineIntegration() async throws {
        let handler: Plug = { conn in
            return conn.respond(status: .ok)
        }
        let conn = makeConn(accept: "application/json")
        let plug = ContentNegotiation(supported: ["application/json"])
        let composed = pipe(plug.asPlug(), handler)
        let result = try await composed(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == "application/json")
    }
}
