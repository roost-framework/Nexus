import Testing
import HTTPTypes
import Foundation
@testable import Nexus
@testable import NexusTest

/// Tests for Connection edge cases and mutation patterns
@Suite("Connection Edge Cases")
struct ConnectionEdgeCasesTests {

    // MARK: - halted() Edge Cases

    @Test("halted() preserves other fields")
    func haltedPreservesOtherFields() {
        var conn = Connection.make(
            method: .post,
            path: "/test",
            body: .buffered(Data("test".utf8))
        )
        conn = conn.assign(key: "test", value: "value")
        conn.response.status = .created

        let halted = conn.halted()

        #expect(halted.isHalted == true)
        #expect(halted.request.method == .post)
        #expect(halted.response.status == .created)
        #expect(halted.assigns["test"] as? String == "value")
    }

    @Test("halted() creates independent copy")
    func haltedCreatesIndependentCopy() {
        let original = Connection.make()
        var halted = original.halted()

        #expect(original.isHalted == false)
        #expect(halted.isHalted == true)

        // Modifying halted should not affect original
        halted.response.status = .internalServerError
        #expect(original.response.status == .ok)
    }

    // MARK: - assign() Edge Cases

    @Test("assign() overwrites existing key")
    func assignOverwritesExistingKey() {
        let conn = Connection.make()
        let conn1 = conn.assign(key: "test", value: "first")
        let conn2 = conn1.assign(key: "test", value: "second")

        #expect(conn2.assigns["test"] as? String == "second")
    }

    @Test("assign() with nil value")
    func assignWithNilValue() {
        let conn = Connection.make()
        let conn2 = conn.assign(key: "optional", value: nil as String?)

        // Nil values should be stored
        #expect(conn2.assigns["optional"] != nil)
    }

    @Test("assign() with complex Sendable types")
    func assignWithComplexSendableTypes() {
        struct CustomStruct: Sendable {
            let id: Int
            let name: String
        }

        let conn = Connection.make()
        let value = CustomStruct(id: 42, name: "test")
        let conn2 = conn.assign(key: "struct", value: value)

        let retrieved = conn2.assigns["struct"] as? CustomStruct
        #expect(retrieved?.id == 42)
        #expect(retrieved?.name == "test")
    }

    @Test("assign() with array values")
    func assignWithArrayValues() {
        let conn = Connection.make()
        let values = [1, 2, 3]
        let conn2 = conn.assign(key: "array", value: values)

        let retrieved = conn2.assigns["array"] as? [Int]
        #expect(retrieved == values)
    }

    @Test("assign() creates independent copy")
    func assignCreatesIndependentCopy() {
        let original = Connection.make()
        var modified = original.assign(key: "test", value: "value")

        #expect(original.assigns.isEmpty)
        #expect(modified.assigns["test"] as? String == "value")

        // Further modifications should not affect original
        modified = modified.assign(key: "another", value: "another")
        #expect(original.assigns.isEmpty)
    }

    // MARK: - Initialization Edge Cases

    @Test("init with empty request body")
    func initWithEmptyRequestBody() {
        let conn = Connection(
            request: HTTPRequest(method: .get, scheme: "http", authority: "localhost", path: "/"),
            requestBody: .empty
        )

        if case .empty = conn.requestBody { } else { Issue.record("Expected .empty") }
    }

    @Test("init with buffered request body")
    func initWithBufferedRequestBody() {
        let data = Data("test".utf8)
        let conn = Connection(
            request: HTTPRequest(method: .post, scheme: "http", authority: "localhost", path: "/"),
            requestBody: .buffered(data)
        )

        guard case let .buffered(retrieved) = conn.requestBody else {
            Issue.record("Expected .buffered"); return
        }
        #expect(retrieved == data)
    }

    @Test("init defaults response to 200 OK")
    func initDefaultsResponseToOK() {
        let conn = Connection(request: HTTPRequest(method: .get, scheme: "http", authority: "localhost", path: "/"))

        #expect(conn.response.status == .ok)
    }

    @Test("init defaults responseBody to empty")
    func initDefaultsResponseBodyToEmpty() {
        let conn = Connection(request: HTTPRequest(method: .get, scheme: "http", authority: "localhost", path: "/"))

        if case .empty = conn.responseBody { } else { Issue.record("Expected .empty") }
    }

    @Test("init defaults isHalted to false")
    func initDefaultsIsHaltedToFalse() {
        let conn = Connection(request: HTTPRequest(method: .get, scheme: "http", authority: "localhost", path: "/"))

        #expect(conn.isHalted == false)
    }

    @Test("init defaults assigns to empty")
    func initDefaultsAssignsToEmpty() {
        let conn = Connection(request: HTTPRequest(method: .get, scheme: "http", authority: "localhost", path: "/"))

        #expect(conn.assigns.isEmpty)
    }

    @Test("init defaults beforeSend to empty")
    func initDefaultsBeforeSendToEmpty() {
        let conn = Connection(request: HTTPRequest(method: .get, scheme: "http", authority: "localhost", path: "/"))

        #expect(conn.beforeSend.isEmpty)
    }

    // MARK: - Value Type Semantics

    @Test("Connection is a value type")
    func connectionIsValueType() {
        var conn1 = Connection.make()
        conn1 = conn1.assign(key: "test", value: "value")

        var conn2 = conn1
        conn2 = conn2.assign(key: "another", value: "another")

        #expect(conn1.assigns["test"] as? String == "value")
        #expect(conn1.assigns["another"] == nil)
        #expect(conn2.assigns["test"] as? String == "value")
        #expect(conn2.assigns["another"] as? String == "another")
    }

    // MARK: - Request/Response Mutation

    @Test("modifying request fields creates new instance")
    func modifyingRequestFields() {
        var conn = Connection.make(method: .get, path: "/old")
        conn.request.path = "/new"

        #expect(conn.request.path == "/new")
    }

    @Test("modifying response fields")
    func modifyingResponseFields() {
        var conn = Connection.make()
        conn.response.status = .created
        conn.response.headerFields = [.contentType: "application/json"]

        #expect(conn.response.status == .created)
        #expect(conn.response.headerFields[.contentType] == "application/json")
    }

    // MARK: - Sendable Conformance

    @Test("Connection is Sendable across actor boundaries")
    func connectionIsSendable() async throws {
        actor TestActor {
            private var stored: Connection?

            func store(_ conn: Connection) {
                stored = conn
            }

            func get() -> Connection? {
                stored
            }
        }

        let actor = TestActor()
        let conn = Connection.make()

        await actor.store(conn)
        let retrieved = await actor.get()

        #expect(retrieved?.request.method == .get)
    }
}
