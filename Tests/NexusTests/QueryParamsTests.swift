import Testing
import HTTPTypes
@testable import Nexus

@Suite("Query Params")
struct QueryParamsTests {

    private func makeConnection(path: String? = "/") -> Connection {
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: "example.com",
            path: path
        )
        return Connection(request: request)
    }

    @Test("test_connection_queryParams_emptyWhenNoQueryString")
    func test_connection_queryParams_emptyWhenNoQueryString() {
        let conn = makeConnection(path: "/users")
        #expect(conn.queryParams.isEmpty)
    }

    @Test("test_connection_queryParams_parsesSingleParam")
    func test_connection_queryParams_parsesSingleParam() {
        let conn = makeConnection(path: "/search?q=donuts")
        #expect(conn.queryParams["q"] == "donuts")
    }

    @Test("test_connection_queryParams_parsesMultipleParams")
    func test_connection_queryParams_parsesMultipleParams() {
        let conn = makeConnection(path: "/search?q=donuts&page=2&limit=10")
        #expect(conn.queryParams["q"] == "donuts")
        #expect(conn.queryParams["page"] == "2")
        #expect(conn.queryParams["limit"] == "10")
    }

    @Test("test_connection_queryParams_lastValueWinsForDuplicates")
    func test_connection_queryParams_lastValueWinsForDuplicates() {
        let conn = makeConnection(path: "/search?q=first&q=second")
        #expect(conn.queryParams["q"] == "second")
    }

    @Test("test_connection_queryParams_percentDecodesKeysAndValues")
    func test_connection_queryParams_percentDecodesKeysAndValues() {
        let conn = makeConnection(path: "/search?q=hello%20world&city=S%C3%A3o%20Paulo")
        #expect(conn.queryParams["q"] == "hello world")
        #expect(conn.queryParams["city"] == "São Paulo")
    }

    @Test("test_connection_queryParams_handlesEmptyValue")
    func test_connection_queryParams_handlesEmptyValue() {
        let conn = makeConnection(path: "/search?active&q=test")
        #expect(conn.queryParams["active"] == "")
        #expect(conn.queryParams["q"] == "test")
    }

    @Test("test_connection_queryParams_handlesNoPath")
    func test_connection_queryParams_handlesNoPath() {
        let conn = makeConnection(path: nil)
        #expect(conn.queryParams.isEmpty)
    }
}
