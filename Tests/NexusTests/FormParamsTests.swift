import Testing
import Foundation
import HTTPTypes
@testable import Nexus

@Suite("Form Params")
struct FormParamsTests {

    private func makeConnection(body: RequestBody = .empty) -> Connection {
        let request = HTTPRequest(
            method: .post,
            scheme: "https",
            authority: "example.com",
            path: "/"
        )
        return Connection(request: request, requestBody: body)
    }

    @Test("test_formParams_emptyWhenBodyIsEmpty")
    func test_formParams_emptyWhenBodyIsEmpty() {
        let conn = makeConnection(body: .empty)
        #expect(conn.formParams.isEmpty)
    }

    @Test("test_formParams_parsesSingleParam")
    func test_formParams_parsesSingleParam() {
        let conn = makeConnection(body: .buffered(Data("name=Alice".utf8)))
        #expect(conn.formParams["name"] == "Alice")
    }

    @Test("test_formParams_parsesMultipleParams")
    func test_formParams_parsesMultipleParams() {
        let conn = makeConnection(body: .buffered(Data("name=Alice&age=30&city=NYC".utf8)))
        #expect(conn.formParams["name"] == "Alice")
        #expect(conn.formParams["age"] == "30")
        #expect(conn.formParams["city"] == "NYC")
    }

    @Test("test_formParams_decodesPlusAsSpace")
    func test_formParams_decodesPlusAsSpace() {
        let conn = makeConnection(body: .buffered(Data("greeting=hello+world".utf8)))
        #expect(conn.formParams["greeting"] == "hello world")
    }

    @Test("test_formParams_percentDecodes")
    func test_formParams_percentDecodes() {
        let conn = makeConnection(body: .buffered(Data("city=S%C3%A3o+Paulo".utf8)))
        #expect(conn.formParams["city"] == "São Paulo")
    }

    @Test("test_formParams_lastValueWinsForDuplicates")
    func test_formParams_lastValueWinsForDuplicates() {
        let conn = makeConnection(body: .buffered(Data("a=1&a=2".utf8)))
        #expect(conn.formParams["a"] == "2")
    }

    @Test("test_formParams_handlesEmptyValue")
    func test_formParams_handlesEmptyValue() {
        let conn = makeConnection(body: .buffered(Data("active&q=test".utf8)))
        #expect(conn.formParams["active"] == "")
        #expect(conn.formParams["q"] == "test")
    }

    @Test("test_formParams_handlesValueWithEquals")
    func test_formParams_handlesValueWithEquals() {
        let conn = makeConnection(body: .buffered(Data("data=a=b=c".utf8)))
        #expect(conn.formParams["data"] == "a=b=c")
    }

    @Test("test_formParams_returnsEmptyForStreamBody")
    func test_formParams_returnsEmptyForStreamBody() {
        let stream = AsyncThrowingStream<Data, any Error> { _ in }
        let conn = makeConnection(body: .stream(stream))
        #expect(conn.formParams.isEmpty)
    }
}
