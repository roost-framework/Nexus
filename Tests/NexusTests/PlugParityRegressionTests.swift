import CNexusZlib
import Foundation
import HTTPTypes
import NexusTest
import Testing

@testable import Nexus

@Suite("Plug parity regressions")
struct PlugParityRegressionTests {
    @Test(arguments: [
        ("https", "example.com:443", "example.com", 443, "https://example.com/a%2Fb?q=x+y"),
        ("http", "localhost:4000", "localhost", 4000, "http://localhost:4000/a%2Fb?q=x+y"),
        ("https", "[::1]", "::1", 443, "https://[::1]/a%2Fb?q=x+y"),
        ("http", "[2001:db8::1]:8080", "2001:db8::1", 8080, "http://[2001:db8::1]:8080/a%2Fb?q=x+y"),
    ])
    func test_metadata_authority_buildsURL(_ value: (String, String, String, Int, String)) {
        let conn = Connection(
            request: HTTPRequest(
                method: .get, scheme: value.0, authority: value.1, path: "/a%2Fb?q=x+y"
            ))
        #expect(conn.host == value.2)
        #expect(conn.port == value.3)
        #expect(conn.requestURL == value.4)
        #expect(conn.requestPath == "/a%2Fb")
        #expect(conn.pathInfo == ["a%2Fb"])
        #expect(conn.queryString == "q=x+y")
    }

    @Test(arguments: ["example.com:-1", "example.com:65536", "[::1]:abc", "example.com:"])
    func test_metadata_invalidPort_returnsNil(_ authority: String) {
        let conn = Connection(request: HTTPRequest(method: .get, scheme: "http", authority: authority, path: "/"))
        #expect(conn.port == nil)
    }

    @Test func test_headers_mergePrependUpdate_preservesValueSemantics() {
        let original = Connection.make(headers: [.accept: "text/plain"])
        let headers = HTTPFields([
            HTTPField(name: .accept, value: "text/html"),
            HTTPField(name: .accept, value: "application/json"),
        ])
        let prepended = original.prependReqHeaders(headers)
        #expect(prepended.getReqHeaders(.accept) == ["text/html", "application/json", "text/plain"])
        #expect(original.mergeReqHeaders(headers).getReqHeaders(.accept) == ["application/json"])
        let updated = prepended.updateReqHeader(.accept, initial: "unused") { $0 + ";q=0.5" }
        #expect(updated.getReqHeaders(.accept).count == 3)
        #expect(updated.getReqHeaders(.accept) == ["text/html;q=0.5", "application/json", "text/plain"])
        #expect(original.getReqHeaders(.accept) == ["text/plain"])
        let cookies = HTTPFields([HTTPField(name: .setCookie, value: "a=1"), HTTPField(name: .setCookie, value: "b=2")])
        let response = original.prependRespHeaders(cookies).updateRespHeader(.setCookie, initial: "unused") {
            $0 + "; Secure"
        }
        #expect(response.getRespHeaders(.setCookie) == ["a=1; Secure", "b=2"])
        #expect(response.mergeRespHeaders([.contentType: "text/plain"]).getRespHeaders(.setCookie).count == 2)
    }

    @Test func test_headers_absentUpdate_doesNotTransformInitial() {
        let conn = Connection.make().updateRespHeader(.vary, initial: "Accept") { _ in
            Issue.record("Transform must not run for a missing header")
            return "wrong"
        }
        #expect(conn.getRespHeader(.vary) == "Accept")
        #expect(
            conn.putRespContentType("text/html", charset: "utf-8").getRespHeader(.contentType)
                == "text/html; charset=utf-8")
    }

    @Test func test_privateData_collidingAssign_remainsSeparate() {
        let conn = Connection.make().assign(key: "key", value: "application")
        let result = conn.putPrivate("key", value: "framework").mergePrivate(["key": "updated"])
        #expect(conn.privateData.isEmpty)
        #expect(result.privateData["key"] as? String == "updated")
        #expect(result.assigns["key"] as? String == "application")
    }

    @Test func test_query_formEncoding_usesPlugPrecedence() {
        let conn = Connection.make(path: "/?a=first&a=last&phrase=hello+world&plus=%2B&=empty-key&empty=&x=a=b")
        #expect(conn.queryParams["a"] == "last")
        #expect(conn.queryParams["phrase"] == "hello world")
        #expect(conn.queryParams["plus"] == "+")
        #expect(conn.queryParams[""] == "empty-key")
        #expect(conn.queryParams["empty"] == "")
        #expect(conn.queryParams["x"] == "a=b")
        #expect(conn.queryParameters["a"] == ["first", "last"])
        #expect(conn.queryParameters["phrase"] == ["hello world"])
        let merged = conn.assign(BodyParamsKey.self, value: ["a": "body"]).mergeParams(["a": "path"])
        #expect(merged.parameters["a"] == ["path"])
        #expect(conn.assign(BodyParamsKey.self, value: ["a": "body"]).getParameter("a") == "body")
    }

    @Test(arguments: [
        ("application/json;q=0, */*;q=1", "text/html"),
        ("text/*;q=0.9, text/html;q=0.1, application/json;q=0.5", "application/json"),
        ("Application/JSON", "application/json"),
        ("text/html;q=NaN, application/json;q=0.5", "application/json"),
        ("text/html;q=2, application/json;q=0.5", "application/json"),
        ("application/jsonx, text/html", "text/html"),
        ("text/html;level=1, application/json", "application/json"),
    ])
    func test_accept_precedence_selectsAcceptableType(_ value: (String, String)) async throws {
        let conn = Connection.make(headers: [.accept: value.0]).putRespHeader(.vary, "Origin")
        let result = try await ContentNegotiation(supported: ["application/json", "text/html"]).call(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == value.1)
        #expect(conn.accepts(value.1))
        #expect(result.getRespHeader(.vary) == "Origin, Accept")
    }

    @Test func test_accept_rejectedWildcard_returns406AndFalse() async throws {
        let conn = Connection.make(headers: [.accept: "text/html;q=0, */*;q=0"])
        #expect(!conn.accepts("text/html"))
        let result = try await ContentNegotiation(supported: ["text/html"]).call(conn)
        #expect(result.response.status == .notAcceptable)
        #expect(result.isHalted)
    }

    @Test func test_accept_parametersAndQuotedDelimiters_matchPrecisely() async throws {
        let type = "text/html;profile=\"a,b;c\""
        let conn = Connection.make(headers: [.accept: "text/html;profile=\"a,b;c\";q=0.8, text/html;q=0.1"])
        let result = try await ContentNegotiation(supported: ["text/html", type]).call(conn)
        #expect(result[ContentNegotiation.NegotiatedTypeKey.self] == type)
        #expect(Connection.make(headers: [.accept: "text/html;q=0.1, application/json;q=0.9"]).prefersHTML == false)
    }

    @Test(arguments: ["gzip", "deflate"])
    func test_compression_wireFormat_decompresses(_ encoding: String) async throws {
        let original = Data(String(repeating: "Nexus gzip must be valid on the wire. ", count: 100).utf8)
        let conn = Connection.make(headers: [.acceptEncoding: encoding])
            .respond(status: .ok, body: .buffered(original)).putRespHeader(.eTag, "\"original\"")
        let result = try await Compression(minimumLength: 1).call(conn).runBeforeSend()
        guard case .buffered(let encoded) = result.responseBody else {
            Issue.record("Missing compressed body")
            return
        }
        #expect(encoded.count < original.count)
        #expect(try inflateBody(encoded, capacity: original.count) == original)
        #expect(result.getRespHeader(.contentEncoding) == encoding)
        #expect(result.getRespHeader(.eTag) == "W/\"original\"")
        #expect(result.getRespHeader(.vary) == "Accept-Encoding")
    }

    @Test(arguments: [
        ("gzip;q=0, deflate;q=0.5", "deflate"),
        ("gzip;q=0.2, deflate;q=0.8", "deflate"),
        ("*;q=0.5", "gzip"),
        ("gzip;q=0, *;q=1", "deflate"),
        ("notgzip", ""),
        ("gzip;q=0", ""),
        ("gzip;q=0.5, identity;q=1", ""),
    ])
    func test_compression_quality_negotiatesTokens(_ value: (String, String)) async throws {
        let conn = Connection.make(headers: [.acceptEncoding: value.0])
            .respond(status: .ok, body: .string(String(repeating: "x", count: 2048)))
        let result = try await Compression().call(conn).runBeforeSend()
        #expect(result.getRespHeader(.contentEncoding) == (value.1.isEmpty ? nil : value.1))
        #expect(result.getRespHeader(.vary) == "Accept-Encoding")
    }

    @Test func test_compression_existingEncodingAndNoTransform_preservesBytes() async throws {
        let base = Connection.make(headers: [.acceptEncoding: "gzip"])
            .respond(status: .ok, body: .string(String(repeating: "x", count: 2048)))
        for conn in [
            base.putRespHeader(.contentEncoding, "br"), base.putRespHeader(.cacheControl, "public, no-transform"),
        ] {
            let result = try await Compression().call(conn).runBeforeSend()
            if case .buffered(let before) = conn.responseBody, case .buffered(let after) = result.responseBody {
                #expect(before == after)
            } else {
                Issue.record("Missing body")
            }
            #expect(result.getRespHeader(.contentEncoding) == conn.getRespHeader(.contentEncoding))
        }
        let varied = try await Compression().call(base.deleteReqHeader(.acceptEncoding)).runBeforeSend()
        #expect(varied.getRespHeader(.vary) == "Accept-Encoding")
    }

    @Test func test_session_repeatedFetchAndPlug_preservesChanges() async throws {
        let config = SessionConfig(secret: Data(repeating: 7, count: 32))
        let plug = sessionPlug(config)
        let fetched = try await plug(Connection.make())
        let changed = fetched.putSession(key: "user", value: "42").fetchSession(config)
        let result = try await plug(changed).runBeforeSend()
        #expect(result.getSession() == ["user": "42"])
        #expect(result.getRespHeaders(.setCookie).count == 1)
        let cookie = try #require(result.getRespHeaders(.setCookie).first)
        let token = try #require(cookie.split(separator: ";").first)
        let recycled = try await plug(Connection.make(headers: [.cookie: String(token)]))
        #expect(recycled.getSession("user") == "42")
        #expect(recycled.runBeforeSend().getRespHeaders(.setCookie).isEmpty)
        #expect(recycled.renewSession().runBeforeSend().getRespHeaders(.setCookie).count == 1)
    }

    @Test func test_session_clearDropIgnore_haveDistinctPersistence() async throws {
        let conn = try await sessionPlug(SessionConfig(secret: Data(repeating: 9, count: 32)))(Connection.make())
            .putSession(key: "user", value: "42")
        let cleared = conn.clearSession(drop: false).runBeforeSend()
        #expect(cleared.getSession().isEmpty)
        #expect(cleared.getRespHeaders(.setCookie).count == 1)
        #expect(cleared.getRespHeader(.setCookie)?.contains("Max-Age=0") == false)
        let dropped = conn.configureSession(drop: true).runBeforeSend()
        #expect(dropped.getRespHeader(.setCookie)?.contains("Max-Age=0") == true)
        let ignored = conn.configureSession(ignore: true).runBeforeSend()
        #expect(ignored.getSession("user") == "42")
        #expect(ignored.getRespHeaders(.setCookie).isEmpty)
    }

    @Test(arguments: [(true, true, true), (true, false, true), (false, true, true)])
    func test_session_combinedOptions_followPlugPrecedence(_ flags: (Bool, Bool, Bool)) async throws {
        let config = SessionConfig(secret: Data(repeating: 9, count: 32))
        let conn = try await sessionPlug(config)(Connection.make()).putSession(key: "user", value: "42")
        let result = conn.configureSession(renew: flags.0, drop: flags.1, ignore: flags.2).runBeforeSend()
        let cookie = try #require(result.getRespHeaders(.setCookie).first)
        #expect(cookie.contains("Max-Age=0") == !flags.0)
        #expect(result.getSession("user") == "42")
    }

    @Test(arguments: [0.0, -1, Double.nan, -Double.infinity])
    func test_timeout_invalidOrZeroDuration_expiresWithoutRunning(_ seconds: Double) async {
        await #expect(throws: Timeout.TimeoutError.self) {
            try await Timeout(seconds: seconds).wrap { conn in
                Issue.record("An expired timeout must not start the plug")
                return conn
            }(Connection.make())
        }
    }

    @Test func test_timeout_extremeDurationAndHaltedInput_doNotTrap() async throws {
        let result = try await Timeout(seconds: .infinity).wrap { $0 }(Connection.make())
        #expect(!result.isHalted)
        let halted = Connection.make().respond(status: .forbidden)
        let result2 = try await Timeout(seconds: 0).wrap { _ in
            Issue.record("Must not run")
            return halted
        }(halted)
        #expect(result2.response.status == .forbidden)
    }

    @Test func test_favicon_headConditionalAndMethod_preservesHTTPContract() async throws {
        let icon = Data([0, 1, 2, 3])
        let plug = Favicon(iconData: icon)
        let get = try await plug.call(Connection.make(path: "/favicon.ico").putRespHeader(.vary, "Origin"))
        let tag = try #require(get.getRespHeader(.eTag))
        #expect(get.getRespHeader(.vary) == "Origin")
        let head = try await plug.call(Connection.make(method: .head, path: "/favicon.ico"))
        #expect(head.getRespHeader(.contentLength) == "4")
        if case .empty = head.responseBody {} else { Issue.record("HEAD must not have a body") }
        for validator in [tag, "W/" + tag, "\"other\", " + tag, "*"] {
            let conditional = try await plug.call(
                Connection.make(path: "/favicon.ico", headers: [.ifNoneMatch: validator]))
            #expect(conditional.response.status == .notModified)
            if case .empty = conditional.responseBody {} else { Issue.record("304 must not have a body") }
        }
        for method: HTTPRequest.Method in [.post, .put, .delete] {
            let result = try await plug.call(Connection.make(method: method, path: "/favicon.ico"))
            #expect(!result.isHalted)
        }
    }
}

private func inflateBody(_ data: Data, capacity: Int) throws -> Data {
    var stream = z_stream()
    let initialized = inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    try #require(initialized == Z_OK)
    defer { inflateEnd(&stream) }
    var output = Data(count: capacity)
    let status = data.withUnsafeBytes { input in
        output.withUnsafeMutableBytes { buffer in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)
            stream.next_out = buffer.bindMemory(to: UInt8.self).baseAddress
            stream.avail_out = uInt(buffer.count)
            return inflate(&stream, Z_FINISH)
        }
    }
    try #require(status == Z_STREAM_END)
    output.count = Int(stream.total_out)
    return output
}
