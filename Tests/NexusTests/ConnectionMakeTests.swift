import Testing
import HTTPTypes
import Foundation
@testable import Nexus
@testable import NexusTest

@Suite("Connection.make() Convenience Builders")
struct ConnectionMakeTests {

    @Test("make() creates basic connection")
    func makeBasicConnection() async throws {
        let conn = Connection.make(
            method: .get,
            path: "/test"
        )

        #expect(conn.request.method == .get)
        #expect(conn.request.path == "/test")
    }

    @Test("make() with all parameters")
    func makeConnectionWithAllParameters() async throws {
        let data = Data("test body".utf8)
        let conn = Connection.make(
            method: .post,
            path: "/test",
            headers: HTTPFields([HTTPField(name: HTTPField.Name("x-custom")!, value: "value")]),
            body: .buffered(data),
            remoteIP: "127.0.0.1",
            assigns: ["userId": "123"]
        )

        #expect(conn.request.method == HTTPRequest.Method.post)
        #expect(conn.request.path == "/test")
        #expect(conn.request.headerFields[HTTPField.Name("x-custom")!] == "value")
        #expect(conn.assigns["userId"] as? String == "123")
    }

    @Test("makeJSON() with string")
    func makeJSONWithString() async throws {
        let conn = Connection.makeJSON(
            method: .post,
            path: "/api/users",
            json: #"{"name":"Alice"}"#
        )

        #expect(conn.request.method == .post)
        #expect(conn.request.path == "/api/users")
        #expect(conn.request.headerFields[.contentType] as String? == "application/json")
    }

    @Test("makeJSON() with Encodable object")
    func makeJSONWithEncodable() async throws {
        struct User: Codable {
            let name: String
            let email: String
        }

        let conn = try Connection.makeJSON(
            method: .post,
            path: "/api/users",
            body: User(name: "Alice", email: "alice@example.com")
        )

        #expect(conn.request.method == .post)
        #expect(conn.request.path == "/api/users")
        #expect(conn.request.headerFields[.contentType] as String? == "application/json")
    }

    @Test("makeJSON() with Encodable and assigns")
    func makeJSONWithEncodableAndAssigns() async throws {
        struct User: Codable {
            let name: String
        }

        let conn = try Connection.makeJSON(
            method: .post,
            path: "/api/users",
            body: User(name: "Alice"),
            remoteIP: "192.168.1.1",
            assigns: ["authenticated": "true"]
        )

        #expect(conn.request.method == .post)
        #expect(conn.assigns["authenticated"] as? String == "true")
    }

    @Test("makeForm() with form string")
    func makeFormWithString() async throws {
        let conn = Connection.makeForm(
            method: .post,
            path: "/login",
            form: "username=alice&password=secret"
        )

        #expect(conn.request.method == .post)
        #expect(conn.request.path == "/login")
        #expect(conn.request.headerFields[.contentType] as String? == "application/x-www-form-urlencoded")
    }

    @Test("makeForm() with fields dictionary")
    func makeFormWithFieldsDictionary() async throws {
        let conn = Connection.makeForm(
            path: "/login",
            fields: ["username": "alice", "password": "secret"]
        )

        #expect(conn.request.method == .post)
        #expect(conn.request.path == "/login")
        #expect(conn.request.headerFields[.contentType] as String? == "application/x-www-form-urlencoded")
    }

    @Test("makeForm() with fields and assigns")
    func makeFormWithFieldsAndAssigns() async throws {
        let conn = Connection.makeForm(
            path: "/login",
            fields: ["username": "alice", "password": "secret"],
            remoteIP: "10.0.0.1",
            assigns: ["loginAttempt": "1"]
        )

        #expect(conn.request.method == .post)
        #expect(conn.assigns["loginAttempt"] as? String == "1")
    }
}
