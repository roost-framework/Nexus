import HTTPTypes
import SwiftCheck
import Testing

@testable import Nexus

/// Property-based tests for Connection value semantics and invariants.
///
/// These tests verify that Connection behaves correctly as a value type,
/// maintaining expected invariants across various operations.
@Suite("Connection Properties")
struct ConnectionProperties {

    // MARK: - Basic Properties

    @Test("connection init creates unhalted connection")
    func connectionInitCreatesUnhaltedConnection() {
        assertProperty(
            forAll { (request: HTTPRequest) in
                let conn = Connection(request: request)
                return conn.isHalted == false
            })
    }

    @Test("connection halted is idempotent")
    func connectionHaltedIsIdempotent() {
        assertProperty(
            forAll { (request: HTTPRequest) in
                let conn = Connection(request: request)
                let once = conn.halted()
                let thrice = conn.halted().halted().halted()

                return once.isHalted == thrice.isHalted && once.isHalted == true
            })
    }

    @Test("connection assign preserves previous assigns")
    func connectionAssignPreservesPreviousAssigns() {
        assertProperty(
            forAll {
                (key1: String, value1: String, key2: String, value2: String) in

                guard !key1.isEmpty && !key2.isEmpty else {
                    return Discard()
                }

                let conn = Connection(
                    request: HTTPRequest(
                        method: .get,
                        scheme: "https",
                        authority: "example.com",
                        path: "/"
                    ))

                let updated =
                    conn
                    .assign(key: key1, value: value1)
                    .assign(key: key2, value: value2)

                let firstPresent = updated.assigns[key1] as? String == (key1 == key2 ? value2 : value1)
                let secondPresent = updated.assigns[key2] as? String == value2

                return firstPresent && secondPresent
            })
    }

    // MARK: - Value Semantics

    @Test("connection mutations return new instances")
    func connectionMutationsReturnNewInstances() {
        assertProperty(
            forAll {
                (request: HTTPRequest, key: String, value: String) in

                guard !key.isEmpty else {
                    return Discard()
                }

                let original = Connection(request: request)
                let modified = original.assign(key: key, value: value)

                // Original should not have the new assign
                let originalUnchanged = original.assigns[key] == nil
                // Modified should have the new assign
                let modifiedChanged = modified.assigns[key] as? String == value

                return originalUnchanged && modifiedChanged
            })
    }
}
