import Testing
import HTTPTypes
import Foundation
@testable import Nexus
@testable import NexusTest
@testable import NexusRouter

@Suite("Public APIs Coverage")
struct PublicAPIsCoverageTests {

    // MARK: - Connection Public APIs

    @Test("Connection init with all defaults")
    func connectionInitDefaults() {
        let request = HTTPRequest(method: .get, scheme: "http", authority: "localhost", path: "/test")
        let conn = Connection(request: request)

        #expect(conn.request == request)
        #expect(conn.response.status == .ok)
        #expect(conn.isHalted == false)
        #expect(conn.assigns.isEmpty)
        #expect(conn.beforeSend.isEmpty)
        if case .empty = conn.requestBody { } else { Issue.record("Expected .empty requestBody") }
        if case .empty = conn.responseBody { } else { Issue.record("Expected .empty responseBody") }
    }

    @Test("Connection init with custom body")
    func connectionInitCustomBody() {
        let request = HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: "/test")
        let body = RequestBody.buffered(Data("test".utf8))
        let conn = Connection(request: request, requestBody: body)

        guard case let .buffered(data) = conn.requestBody else {
            Issue.record("Expected .buffered requestBody")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "test")
    }

    // MARK: - Connection+QueryParams

    @Test("query parameter extraction")
    func queryParameterExtraction() {
        let conn = Connection.make(path: "/test?key=value&foo=bar")
        let queryParams = conn.queryParams
        #expect(queryParams["key"] == "value")
        #expect(queryParams["foo"] == "bar")
    }

    @Test("query parameter with no value")
    func queryParameterNoValue() {
        let conn = Connection.make(path: "/test?key")
        let queryParams = conn.queryParams
        #expect(queryParams["key"] == "")
    }

    @Test("query parameter with multiple values")
    func queryParameterMultipleValues() {
        let conn = Connection.make(path: "/test?key=value1&key=value2")
        let queryParams = conn.queryParams
        #expect(queryParams["key"] != nil)
    }

    @Test("query parameter with encoded values")
    func queryParameterEncodedValues() {
        let conn = Connection.make(path: "/test?key=hello%20world")
        let queryParams = conn.queryParams
        #expect(queryParams["key"] == "hello world")
    }

    // MARK: - Connection+Respond

    @Test("respond with status only")
    func respondWithStatusOnly() {
        let conn = Connection.make()
        let result = conn.respond(status: .created)
        #expect(result.response.status == .created)
        #expect(result.isHalted == true)
    }

    @Test("respond with status and body")
    func respondWithStatusAndBody() {
        let conn = Connection.make()
        let result = conn.respond(status: .ok, body: .string("test"))
        #expect(result.response.status == .ok)
        guard case let .buffered(data) = result.responseBody else {
            Issue.record("Expected .buffered responseBody")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "test")
        #expect(result.isHalted == true)
    }

    @Test("respond with status body and content type")
    func respondWithStatusBodyAndContentType() {
        let conn = Connection.make()
        let result = conn
            .respond(status: .ok, body: .string("test"))
            .putRespContentType("text/plain")
        #expect(result.response.status == .ok)
        #expect(result.response.headerFields[HTTPField.Name.contentType] == "text/plain")
        #expect(result.isHalted == true)
    }

    // MARK: - Connection+JSON

    @Test("json response with encodable")
    func jsonResponseWithEncodable() throws {
        struct TestStruct: Codable, Sendable {
            let name: String
            let value: Int
        }

        let conn = Connection.make()
        let value = TestStruct(name: "test", value: 42)
        let result = try conn.json(value: value)

        #expect(result.response.status == .ok)
        #expect(result.response.headerFields[HTTPField.Name.contentType] == "application/json")
        guard case let .buffered(data) = result.responseBody else {
            Issue.record("Expected .buffered responseBody")
            return
        }
        let decoded = try JSONDecoder().decode(TestStruct.self, from: data)
        #expect(decoded.name == "test")
        #expect(decoded.value == 42)
        #expect(result.isHalted == true)
    }

    @Test("json response with custom status")
    func jsonResponseWithCustomStatus() throws {
        struct TestStruct: Codable, Sendable {
            let id: Int
        }

        let conn = Connection.make()
        let result = try conn.json(status: .created, value: TestStruct(id: 123))
        #expect(result.response.status == .created)
        #expect(result.response.headerFields[HTTPField.Name.contentType] == "application/json")
    }

    // MARK: - Connection+HTML

    @Test("html response")
    func htmlResponse() {
        let conn = Connection.make()
        let result = conn.html("<h1>Hello</h1>")
        #expect(result.response.status == .ok)
        #expect(result.response.headerFields[HTTPField.Name.contentType]?.hasPrefix("text/html") == true)
        guard case let .buffered(data) = result.responseBody else {
            Issue.record("Expected .buffered responseBody")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "<h1>Hello</h1>")
        #expect(result.isHalted == true)
    }

    // MARK: - Connection+Inform

    @Test("inform response")
    func informResponse() {
        let conn = Connection.make()
        let result = conn.inform(
            status: HTTPResponse.Status(code: 103),
            headers: HTTPFields([HTTPField(name: HTTPField.Name("link")!, value: "</style.css>; rel=preload; as=style")])
        )
        #expect(result.informationalResponses.count == 1)
        #expect(result.informationalResponses[0].status.code == 103)
    }

    // MARK: - Connection+TypedAssigns

    @Test("typed assign convenience")
    func typedAssignConvenience() {
        struct TestState: Sendable {
            var count = 0
        }

        let conn = Connection.make()
        let result = conn.assign(key: "state", value: TestState())
        let state = result.assigns["state"] as? TestState
        #expect(state?.count == 0)
    }

    // MARK: - Route Helper Functions

    @Test("GET route helper")
    func getRouteHelper() {
        let route = GET("/test") { conn in
            conn.respond(status: .ok)
        }
        #expect(route.method == .get)
        #expect(route.path == "/test")
    }

    @Test("POST route helper")
    func postRouteHelper() {
        let route = POST("/test") { conn in
            conn.respond(status: .created)
        }
        #expect(route.method == .post)
        #expect(route.path == "/test")
    }

    @Test("PUT route helper")
    func putRouteHelper() {
        let route = PUT("/test") { conn in
            conn.respond(status: .ok)
        }
        #expect(route.method == .put)
        #expect(route.path == "/test")
    }

    @Test("PATCH route helper")
    func patchRouteHelper() {
        let route = PATCH("/test") { conn in
            conn.respond(status: .ok)
        }
        #expect(route.method == .patch)
        #expect(route.path == "/test")
    }

    @Test("DELETE route helper")
    func deleteRouteHelper() {
        let route = DELETE("/test") { conn in
            conn.respond(status: .noContent)
        }
        #expect(route.method == .delete)
        #expect(route.path == "/test")
    }

    // MARK: - Router Public APIs

    @Test("Router with no routes returns 404")
    func routerNoRoutes404() async throws {
        let router = Router { [] }
        let conn = Connection.make(path: "/test")
        let result = try await router.handle(conn)
        #expect(result.response.status == .notFound)
        #expect(result.isHalted == true)
    }

    @Test("Router with matching route")
    func routerMatchingRoute() async throws {
        let router = Router {
            GET("/test") { conn in
                conn.respond(status: .ok, body: .string("matched"))
            }
        }
        let conn = Connection.make(path: "/test")
        let result = try await router.handle(conn)
        #expect(result.response.status == .ok)
        guard case let .buffered(data) = result.responseBody else {
            Issue.record("Expected .buffered responseBody")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "matched")
    }

    @Test("Router path parameter extraction")
    func routerPathParameterExtraction() async throws {
        let router = Router {
            GET("/users/:id") { conn in
                let id = conn.params["id"] ?? ""
                return conn.respond(status: .ok, body: .string("User \(id)"))
            }
        }
        let conn = Connection.make(path: "/users/123")
        let result = try await router.handle(conn)
        #expect(result.response.status == .ok)
        guard case let .buffered(data) = result.responseBody else {
            Issue.record("Expected .buffered responseBody")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "User 123")
    }

    @Test("Router 405 method not allowed")
    func router405MethodNotAllowed() async throws {
        let router = Router {
            GET("/test") { conn in conn.respond(status: .ok) }
        }
        let conn = Connection.make(method: .post, path: "/test")
        let result = try await router.handle(conn)
        #expect(result.response.status == .methodNotAllowed)
        #expect(result.isHalted == true)
    }

    // MARK: - NamedPipeline

    @Test("NamedPipeline passes connection through")
    func namedPipelinePassesThrough() async throws {
        let namedPipeline = NamedPipeline {
            { conn in
                var copy = conn
                copy.assigns["visited"] = true
                return copy
            }
        }
        let conn = Connection.make()
        let result = try await namedPipeline.call(conn)
        #expect(result.assigns["visited"] as? Bool == true)
    }

    @Test("NamedPipeline with multiple plugs")
    func namedPipelineMultiplePlugs() async throws {
        let namedPipeline = NamedPipeline {
            pipe(
                { conn in
                    var copy = conn
                    copy.assigns["step1"] = true
                    return copy
                },
                { conn in
                    var copy = conn
                    copy.assigns["step2"] = true
                    return copy
                }
            )
        }
        let conn = Connection.make()
        let result = try await namedPipeline.call(conn)
        #expect(result.assigns["step1"] as? Bool == true)
        #expect(result.assigns["step2"] as? Bool == true)
    }

    // MARK: - Error Handling

    @Test("NexusHTTPError public initializer")
    func nexusHTTPErrorInit() {
        let error = NexusHTTPError(.badRequest, message: "Invalid input")
        #expect(error.status == .badRequest)
        #expect(String(describing: error).contains("Invalid input"))
    }

    @Test("NexusHTTPError with custom body")
    func nexusHTTPErrorCustomBody() {
        let error = NexusHTTPError(HTTPResponse.Status(code: 422), message: "validation failed")
        #expect(error.status.code == 422)
    }

    // MARK: - SSE

    @Test("SSEEvent creation")
    func sseEventCreation() {
        let event = SSEEvent(data: "Hello", event: "message", id: "1", retry: 1000)
        #expect(event.id == "1")
        #expect(event.event == "message")
        #expect(event.data == "Hello")
        #expect(event.retry == 1000)
    }

    @Test("SSEEvent formatted output")
    func sseEventFormatted() {
        let event = SSEEvent(data: "test data", event: "update")
        let formatted = event.formatted()
        #expect(formatted.contains("data: test data"))
        #expect(formatted.contains("event: update"))
    }

    // MARK: - Module Conformance

    @Test("Router conforms to ModulePlug")
    func routerModulePlugConformance() async throws {
        let router = Router {
            GET("/test") { $0.respond(status: .ok) }
        }
        let conn = Connection.make(path: "/test")
        let result = try await router(conn)
        #expect(result.response.status == .ok)
    }

    @Test("NamedPipeline conforms to ModulePlug")
    func namedPipelineModulePlugConformance() async throws {
        let namedPipeline = NamedPipeline {
            { conn in conn.respond(status: .ok) }
        }
        let conn = Connection.make()
        let result = try await namedPipeline.call(conn)
        #expect(result.response.status == .ok)
    }

    // MARK: - Cookie Helpers

    @Test("reqCookies access")
    func reqCookiesAccess() {
        let conn = Connection.make(
            headers: HTTPFields([HTTPField(name: .cookie, value: "session=abc123")])
        )
        #expect(conn.reqCookies["session"] == "abc123")
    }

    @Test("putRespCookie adds Set-Cookie header")
    func putRespCookieAddsHeader() {
        let conn = Connection.make()
        let cookie = Cookie(name: "test", value: "value")
        let result = conn.putRespCookie(cookie)
        let setCookieHeaders = result.response.headerFields.filter { $0.name == .setCookie }
        #expect(!setCookieHeaders.isEmpty)
        #expect(setCookieHeaders[0].value.contains("test"))
    }

    @Test("deleteRespCookie adds expiry Set-Cookie header")
    func deleteRespCookieAddsExpiryHeader() {
        let conn = Connection.make()
        let result = conn.deleteRespCookie("session")
        let setCookieHeaders = result.response.headerFields.filter { $0.name == .setCookie }
        #expect(!setCookieHeaders.isEmpty)
        #expect(setCookieHeaders[0].value.contains("Max-Age=0"))
    }

    // MARK: - ResponseBody convenience

    @Test("ResponseBody string with empty string")
    func responseBodyStringEmpty() {
        let body = ResponseBody.string("")
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered body")
            return
        }
        #expect(data.isEmpty)
    }

    @Test("ResponseBody string with special characters")
    func responseBodyStringSpecialCharacters() {
        let input = "Line 1\nLine 2\r\nTab:\tNull: \0End"
        let body = ResponseBody.string(input)
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered body")
            return
        }
        #expect(String(data: data, encoding: .utf8) == input)
    }
}
