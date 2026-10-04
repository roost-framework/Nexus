import Foundation
import HTTPTypes
import Testing

@testable import Nexus
@testable import NexusTest

@Suite("Connection API Parity")
struct ConnectionAPITests {

    // MARK: - getReqHeaders

    @Test("getReqHeaders returns all values for multi-value header")
    func getReqHeadersMultiValue() {
        let conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptLanguage, value: "en"),
                HTTPField(name: .acceptLanguage, value: "fr"),
                HTTPField(name: .acceptLanguage, value: "de"),
            ])
        )
        let values = conn.getReqHeaders(.acceptLanguage)
        #expect(values == ["en", "fr", "de"])
    }

    @Test("getReqHeaders returns single value as one-element array")
    func getReqHeadersSingleValue() {
        let conn = Connection.make(
            headers: HTTPFields([HTTPField(name: .contentType, value: "application/json")])
        )
        #expect(conn.getReqHeaders(.contentType) == ["application/json"])
    }

    @Test("getReqHeaders returns empty array for absent header")
    func getReqHeadersAbsent() {
        let conn = Connection.make()
        #expect(conn.getReqHeaders(.acceptLanguage) == [])
    }

    @Test("getReqHeaders String overload returns all values")
    func getReqHeadersStringOverload() throws {
        let name = try #require(HTTPField.Name("x-custom"))
        let conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: name, value: "a"),
                HTTPField(name: name, value: "b"),
            ])
        )
        #expect(conn.getReqHeaders("x-custom") == ["a", "b"])
    }

    @Test("getReqHeaders String overload with invalid name returns empty")
    func getReqHeadersInvalidName() {
        let conn = Connection.make()
        #expect(conn.getReqHeaders("") == [])
    }

    // MARK: - getRespHeaders

    @Test("getRespHeaders returns all values for multi-value response header")
    func getRespHeadersMultiValue() {
        var conn = Connection.make()
        conn.response.headerFields.append(HTTPField(name: .setCookie, value: "a=1"))
        conn.response.headerFields.append(HTTPField(name: .setCookie, value: "b=2"))
        let values = conn.getRespHeaders(.setCookie)
        #expect(values == ["a=1", "b=2"])
    }

    @Test("getRespHeaders returns empty array for absent header")
    func getRespHeadersAbsent() {
        let conn = Connection.make()
        #expect(conn.getRespHeaders(.setCookie) == [])
    }

    @Test("getRespHeaders String overload returns all values")
    func getRespHeadersStringOverload() throws {
        let name = try #require(HTTPField.Name("x-trace"))
        var conn = Connection.make()
        conn.response.headerFields.append(HTTPField(name: name, value: "1"))
        conn.response.headerFields.append(HTTPField(name: name, value: "2"))
        #expect(conn.getRespHeaders("x-trace") == ["1", "2"])
    }

    // MARK: - port

    @Test("port parsed from authority with explicit port")
    func portFromAuthority() {
        let conn = Connection.make(scheme: "http", authority: "example.com:8080")
        #expect(conn.port == 8080)
    }

    @Test("port defaults to 443 for https with no explicit port")
    func portDefaultsHttps() {
        let conn = Connection.make(scheme: "https", authority: "example.com")
        #expect(conn.port == 443)
    }

    @Test("port defaults to 80 for http with no explicit port")
    func portDefaultsHttp() {
        let conn = Connection.make(scheme: "http", authority: "example.com")
        #expect(conn.port == 80)
    }

    @Test("port returns nil for unknown scheme with no explicit port")
    func portUnknownScheme() {
        let conn = Connection.make(scheme: "ws", authority: "example.com")
        #expect(conn.port == nil)
    }

    @Test("port uses explicit port even for default scheme port")
    func portExplicitOverridesDefault() {
        let conn = Connection.make(scheme: "https", authority: "example.com:8443")
        #expect(conn.port == 8443)
    }

    // MARK: - requestURL

    @Test("requestURL includes scheme, host, and path")
    func requestURLBasic() {
        let conn = Connection.make(scheme: "https", authority: "example.com", path: "/api/users")
        #expect(conn.requestURL == "https://example.com/api/users")
    }

    @Test("requestURL omits default port 443 for https")
    func requestURLOmitsDefaultHttpsPort() {
        let conn = Connection.make(scheme: "https", authority: "example.com:443", path: "/")
        #expect(conn.requestURL == "https://example.com/")
    }

    @Test("requestURL omits default port 80 for http")
    func requestURLOmitsDefaultHttpPort() {
        let conn = Connection.make(scheme: "http", authority: "example.com:80", path: "/")
        #expect(conn.requestURL == "http://example.com/")
    }

    @Test("requestURL includes non-default port")
    func requestURLIncludesNonDefaultPort() {
        let conn = Connection.make(scheme: "http", authority: "localhost:4000", path: "/health")
        #expect(conn.requestURL == "http://localhost:4000/health")
    }

    @Test("requestURL includes query string")
    func requestURLIncludesQuery() {
        let conn = Connection.make(path: "/search?q=nexus&page=1")
        #expect(conn.requestURL.hasSuffix("/search?q=nexus&page=1"))
    }

    @Test("requestURL falls back to sensible defaults for nil components")
    func requestURLDefaults() {
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: nil)
        let conn = Connection(request: request)
        #expect(conn.requestURL == "http://localhost/")
    }

    // MARK: - mergeAssigns

    @Test("mergeAssigns adds new keys")
    func mergeAssignsAddsKeys() {
        let conn = Connection.make().assign(key: "a", value: "1")
        let result = conn.mergeAssigns(["b": "2", "c": "3"])
        #expect(result.assigns["a"] as? String == "1")
        #expect(result.assigns["b"] as? String == "2")
        #expect(result.assigns["c"] as? String == "3")
    }

    @Test("mergeAssigns overwrites existing keys")
    func mergeAssignsOverwrites() {
        let conn = Connection.make().assign(key: "key", value: "old")
        let result = conn.mergeAssigns(["key": "new"])
        #expect(result.assigns["key"] as? String == "new")
    }

    @Test("mergeAssigns with empty dict returns same assigns")
    func mergeAssignsEmpty() {
        let conn = Connection.make().assign(key: "k", value: "v")
        let result = conn.mergeAssigns([:])
        #expect(result.assigns["k"] as? String == "v")
        #expect(result.assigns.count == conn.assigns.count)
    }

    @Test("mergeAssigns does not mutate original")
    func mergeAssignsImmutable() {
        let conn = Connection.make().assign(key: "a", value: "1")
        _ = conn.mergeAssigns(["b": "2"])
        #expect(conn.assigns["b"] == nil)
    }

    // MARK: - renewSession

    @Test("renewSession sets sessionTouchedKey")
    func renewSessionSetsTouched() {
        let conn = Connection.make()
        let renewed = conn.renewSession()
        #expect(renewed.assigns[Connection.sessionTouchedKey] as? Bool == true)
    }

    @Test("renewSession preserves existing session data")
    func renewSessionPreservesData() {
        let conn = Connection.make()
            .assign(key: Connection.sessionKey, value: ["user_id": "42"])
        let renewed = conn.renewSession()
        let session = renewed.assigns[Connection.sessionKey] as? [String: String]
        #expect(session?["user_id"] == "42")
    }

    @Test("renewSession does not halt the connection")
    func renewSessionNoHalt() {
        let conn = Connection.make()
        #expect(!conn.renewSession().isHalted)
    }

    @Test("renewSession does not clear session data")
    func renewSessionNoDropFlag() {
        let conn = Connection.make()
        let renewed = conn.renewSession()
        #expect(renewed.assigns[Connection.sessionDropKey] as? Bool != true)
    }
}

// Helper to build connections with explicit scheme/authority
extension Connection {
    fileprivate static func make(
        scheme: String,
        authority: String,
        path: String = "/"
    ) -> Connection {
        let request = HTTPRequest(method: .get, scheme: scheme, authority: authority, path: path)
        return Connection(request: request)
    }
}
