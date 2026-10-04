import SwiftCheck
import Testing

@Suite("SwiftCheck assertion bridge")
struct PropertyBridgeTests {
    @Test func test_assertProperty_falseProperty_recordsFailure() {
        withKnownIssue("A false property must record a Swift Testing failure") {
            assertProperty(forAll(Gen<Int>.pure(1)) { $0 == 2 })
        }
    }

    @Test func test_assertProperty_discardedProperty_recordsFailure() {
        withKnownIssue("A property without enough successful cases must fail") {
            assertProperty(forAll(Gen<Int>.pure(1)) { _ in Discard() })
        }
    }

    @Test func test_assertProperty_trueProperty_succeeds() {
        assertProperty(forAll(Gen<Int>.pure(1)) { $0 == 1 })
    }
}
