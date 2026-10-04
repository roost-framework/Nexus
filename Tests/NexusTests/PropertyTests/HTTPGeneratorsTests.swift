import HTTPTypes
import SwiftCheck
import Testing

@testable import Nexus
@testable import NexusTest

/// Property tests for HTTPGenerators to verify generator correctness
@Suite("HTTP Generators")
struct HTTPGeneratorsTests {

    @Test("HTTP method generator produces valid methods")
    func HTTPMethodGeneratorProducesValidMethods() {
        assertProperty(
            forAll { (method: HTTPRequest.Method) in
                // Test that we can create a request with the generated method
                let request = HTTPRequest(
                    method: method,
                    scheme: "https",
                    authority: "example.com",
                    path: "/"
                )
                return request.method == method
            })
    }

    @Test("HTTP path generator produces valid paths")
    func HTTPPathGeneratorProducesValidPaths() {
        assertProperty(
            forAll(Gen<String>.httpPath) { path in
                path.hasPrefix("/") && !path.contains("//")
            })
    }

    @Test("HTTP request generator produces complete requests")
    func HTTPRequestGeneratorProducesCompleteRequests() {
        assertProperty(
            forAll { (request: HTTPRequest) in
                !(request.scheme?.isEmpty ?? true) && !(request.authority?.isEmpty ?? true)
                    && !(request.path?.isEmpty ?? true) && (request.path?.hasPrefix("/") ?? false)
            })
    }

    @Test("Connection generator creates valid connections")
    func ConnectionGeneratorCreatesValidConnections() {
        assertProperty(
            forAll { (conn: Connection) in
                !conn.isHalted && !(conn.request.scheme?.isEmpty ?? true) && !(conn.request.authority?.isEmpty ?? true)
            })
    }

    @Test("HTTP field generator produces valid fields")
    func HTTPFieldGeneratorProducesValidFields() {
        assertProperty(
            forAll { (field: HTTPField) in
                // HTTPFields trims surrounding whitespace; an empty field value is valid HTTP.
                !field.name.rawName.isEmpty && field.value.allSatisfy { $0.isASCII }
            })
    }
}
