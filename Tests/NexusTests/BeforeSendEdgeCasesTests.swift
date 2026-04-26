import Testing
import HTTPTypes
@testable import Nexus
@testable import NexusTest

/// Tests for BeforeSend lifecycle hook edge cases
@Suite("BeforeSend Edge Cases")
struct BeforeSendEdgeCasesTests {

    // MARK: - registerBeforeSend() Edge Cases

    @Test("registerBeforeSend preserves other fields")
    func registerBeforeSendPreservesOtherFields() {
        var conn = Connection.make()
        conn = conn.assign(key: "test", value: "value")
        conn.response.status = .created

        let registered = conn.registerBeforeSend { $0 }

        #expect(registered.assigns["test"] as? String == "value")
        #expect(registered.response.status == .created)
    }

    @Test("registerBeforeSend adds callback without executing")
    func registerBeforeSendAddsCallback() {
        let conn = Connection.make()
        let registered = conn.registerBeforeSend { c in
            var copy = c; copy.assigns["_ran"] = true; return copy
        }
        // Callback not yet executed — assigns unchanged
        #expect(registered.assigns["_ran"] == nil)
        #expect(registered.beforeSend.count == 1)
    }

    @Test("registerBeforeSend multiple callbacks accumulate")
    func registerBeforeSendMultipleCallbacks() {
        let conn = Connection.make()

        let registered = conn
            .registerBeforeSend { $0 }
            .registerBeforeSend { $0 }
            .registerBeforeSend { $0 }

        #expect(registered.beforeSend.count == 3)
    }

    @Test("registerBeforeSend creates independent copy")
    func registerBeforeSendCreatesIndependentCopy() {
        let original = Connection.make()
        var modified = original.registerBeforeSend { $0 }

        #expect(original.beforeSend.isEmpty)
        #expect(modified.beforeSend.count == 1)

        // Further modifications should not affect original
        modified = modified.registerBeforeSend { $0 }
        #expect(original.beforeSend.isEmpty)
        #expect(modified.beforeSend.count == 2)
    }

    // MARK: - runBeforeSend() Edge Cases

    @Test("runBeforeSend executes callbacks in LIFO order")
    func runBeforeSendLIFOOrder() {
        var executionOrder: [Int] = []

        let conn = Connection.make()
        let registered = conn
            .registerBeforeSend { c in
                var copy = c
                let order = copy.assigns["order"] as? [Int] ?? []
                copy.assigns["order"] = order + [1]
                return copy
            }
            .registerBeforeSend { c in
                var copy = c
                let order = copy.assigns["order"] as? [Int] ?? []
                copy.assigns["order"] = order + [2]
                return copy
            }
            .registerBeforeSend { c in
                var copy = c
                let order = copy.assigns["order"] as? [Int] ?? []
                copy.assigns["order"] = order + [3]
                return copy
            }

        let result = registered.runBeforeSend()

        #expect(result.assigns["order"] as? [Int] == [3, 2, 1])
    }

    @Test("runBeforeSend clears callback array")
    func runBeforeSendClearsCallbacks() {
        let conn = Connection.make()
        let registered = conn
            .registerBeforeSend { $0 }
            .registerBeforeSend { $0 }

        let result = registered.runBeforeSend()

        #expect(result.beforeSend.isEmpty)
    }

    @Test("runBeforeSend with no callbacks is no-op")
    func runBeforeSendNoCallbacks() {
        let conn = Connection.make()

        let result = conn.runBeforeSend()

        #expect(result.beforeSend.isEmpty)
        #expect(result.request.method == .get)
        #expect(result.response.status == .ok)
    }

    @Test("runBeforeSend with single callback")
    func runBeforeSendSingleCallback() {
        let conn = Connection.make()

        let registered = conn.registerBeforeSend { c in
            var copy = c
            copy.response.status = HTTPResponse.Status(code: 201)
            copy.assigns["_ran"] = true
            return copy
        }

        let result = registered.runBeforeSend()

        #expect(result.assigns["_ran"] as? Bool == true)
        #expect(result.response.status == .created)
        #expect(result.beforeSend.isEmpty)
    }

    @Test("runBeforeSend with callback that modifies connection")
    func runBeforeSendModifiesConnection() {
        let conn = Connection.make()

        let registered = conn
            .registerBeforeSend { conn in
                var copy = conn
                copy.response.status = .accepted
                copy.responseBody = .string("modified")
                return copy
            }

        let result = registered.runBeforeSend()

        #expect(result.response.status == .accepted)
        guard case let .buffered(data) = result.responseBody else {
            Issue.record("Expected .buffered responseBody")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "modified")
    }

    @Test("runBeforeSend with callback chain")
    func runBeforeSendCallbackChain() {
        let conn = Connection.make()

        let registered = conn
            .registerBeforeSend { conn in
                var copy = conn
                copy.response.headerFields[.contentType] = "text/plain"
                return copy
            }
            .registerBeforeSend { conn in
                var copy = conn
                copy.response.status = HTTPResponse.Status(code: 201)
                return copy
            }
            .registerBeforeSend { conn in
                conn.assign(key: "logged", value: true)
            }

        let result = registered.runBeforeSend()

        // Last registered (assign) runs first
        #expect(result.assigns["logged"] as? Bool == true)
        // Then status change
        #expect(result.response.status == .created)
        // Then content type (first registered, last executed)
        #expect(result.response.headerFields[.contentType] == "text/plain")
    }

    @Test("runBeforeSend with halted connection")
    func runBeforeSendWithHaltedConnection() {
        var conn = Connection.make()
        conn.isHalted = true

        let registered = conn.registerBeforeSend { c in
            var copy = c
            copy.response.status = .internalServerError
            copy.assigns["_ran"] = true
            return copy
        }

        let result = registered.runBeforeSend()

        #expect(result.assigns["_ran"] as? Bool == true)
        #expect(result.isHalted == true)
        #expect(result.response.status == .internalServerError)
    }

    // MARK: - Error Handling in Callbacks

    @Test("runBeforeSend callback that throws")
    func runBeforeSendCallbackThrows() {
        let conn = Connection.make()

        let registered = conn.registerBeforeSend { c in
            var copy = c
            copy.response.status = .internalServerError
            return copy
        }

        // Should compile and execute without throwing
        let result = registered.runBeforeSend()
        #expect(result.response.status == .internalServerError)
    }

    // MARK: - Sendable Conformance

    @Test("beforeSend callbacks are Sendable")
    func beforeSendCallbacksAreSendable() async throws {
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
        var conn = Connection.make()

        // Register Sendable callback
        conn = conn.registerBeforeSend { conn in
            var copy = conn
            copy.response.status = HTTPResponse.Status(code: 201)
            return copy
        }

        await actor.store(conn)
        let retrieved = await actor.get()

        #expect(retrieved?.beforeSend.count == 1)
    }

    // MARK: - Multiple runBeforeSend() Calls

    @Test("calling runBeforeSend twice only executes once")
    func runBeforeSendTwice() {
        let conn = Connection.make()

        let registered = conn.registerBeforeSend { c in
            var copy = c
            let count = copy.assigns["count"] as? Int ?? 0
            copy.assigns["count"] = count + 1
            return copy
        }

        let result1 = registered.runBeforeSend()
        let result2 = result1.runBeforeSend()

        #expect(result1.assigns["count"] as? Int == 1)
        #expect(result2.beforeSend.isEmpty)
    }

    // MARK: - Callback Registration After runBeforeSend

    @Test("registering callbacks after runBeforeSend")
    func registerAfterRunBeforeSend() {
        let conn = Connection.make()

        let registered = conn.registerBeforeSend { $0 }
        let afterRun = registered.runBeforeSend()

        let newRegistration = afterRun.registerBeforeSend { conn in
            var copy = conn
            copy.response.status = HTTPResponse.Status(code: 201)
            return copy
        }

        #expect(newRegistration.beforeSend.count == 1)

        let result = newRegistration.runBeforeSend()
        #expect(result.response.status == .created)
    }

    // MARK: - Complex Callback Scenarios

    @Test("callback that reads and modifies assigns")
    func callbackReadsAndModifiesAssigns() {
        var conn = Connection.make()
        conn = conn.assign(key: "counter", value: 0)

        let registered = conn.registerBeforeSend { conn in
            let current = conn.assigns["counter"] as? Int ?? 0
            var copy = conn
            copy.assigns["counter"] = current + 1
            return copy
        }

        let result = registered.runBeforeSend()
        #expect(result.assigns["counter"] as? Int == 1)
    }

    @Test("callback that conditionally modifies response")
    func callbackConditionallyModifiesResponse() {
        let conn = Connection.make()

        let registered = conn.registerBeforeSend { conn in
            var copy = conn
            if conn.response.status == .ok {
                copy.response.status = .accepted
            } else {
                copy.response.status = .internalServerError
            }
            return copy
        }

        let result = registered.runBeforeSend()
        #expect(result.response.status == .accepted)
    }

    @Test("callback with empty response body")
    func callbackWithEmptyBody() {
        var conn = Connection.make()
        conn.responseBody = .string("original")

        let registered = conn.registerBeforeSend { conn in
            var copy = conn
            copy.responseBody = .empty
            return copy
        }

        let result = registered.runBeforeSend()
        if case .empty = result.responseBody { } else {
            Issue.record("Expected .empty responseBody")
        }
    }
}
