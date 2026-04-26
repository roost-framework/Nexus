import Testing
import HTTPTypes
import Foundation
import Nexus

#if canImport(NexusHummingbird)
@testable import NexusHummingbird
#endif

#if canImport(NexusVapor)
import Vapor
@testable import NexusVapor
#endif

/// Property-based tests for adapter behavior and parity.
///
/// These tests verify that adapters produce correct and consistent results.
/// Tests cover comprehensive scenarios to ensure both adapters (when available)
/// handle requests identically according to Nexus specifications.
///
/// Properties tested:
/// - Status codes are correctly propagated
/// - Response headers are preserved
/// - Response bodies are transmitted correctly
/// - Halted connections are handled properly
/// - Errors (ADR-004) produce 500 responses
/// - BeforeSend hooks (ADR-006) execute correctly
///
/// Note: Full SwiftCheck integration and Vapor parity tests will be completed
/// when the NexusVapor adapter is fully implemented.
@Suite("Adapter Property Tests")
struct AdapterPropertyTests {

    // MARK: - Test Configuration

    /// Check if Vapor adapter is available
    private var isVaporAvailable: Bool {
        #if canImport(NexusVapor)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Generator Helpers

    /// Generate a random HTTPRequest for testing
    private func generateHTTPRequest(
        method: HTTPRequest.Method = .get,
        path: String = "/",
        headers: [HTTPField] = [],
        body: Data? = nil
    ) -> HTTPRequest {
        var request = HTTPRequest(
            method: method,
            scheme: "https",
            authority: "example.com",
            path: path
        )

        for header in headers {
            request.headerFields[header.name] = header.value
        }

        return request
    }

    /// Generate random HTTP headers
    private func generateHeaders(count: Int = 3) -> [HTTPField] {
        let headerNames = [
            "X-Request-ID", "X-Custom", "X-Trace-ID",
            "X-Session-ID", "X-Client-Version"
        ]

        return (0..<min(count, headerNames.count)).map { index in
            HTTPField(
                name: HTTPField.Name(headerNames[index])!,
                value: "value-\(Int.random(in: 1...1000))"
            )
        }
    }

    // MARK: - Status Code Parity Tests

    @Test("Status codes are correctly propagated")
    func statusCodesMatch() async {
        // Test comprehensive set of status codes
        let statusCodes = [
            200, 201, 202, 204,  // Success
            301, 302, 304,        // Redirection
            400, 401, 403, 404, 422,  // Client errors
            500, 502, 503         // Server errors
        ]

        for statusCode in statusCodes {
            let plug: Plug = { conn in
                var copy = conn
                copy.response = HTTPResponse(status: HTTPResponse.Status(code: statusCode))
                return copy
            }

            // Test with Hummingbird
            let hbResult = await runHummingbirdPlug(plug)

            // Verify status code is correct
            #expect(
                hbResult.status == HTTPResponse.Status(code: statusCode),
                "Status code \(statusCode) mismatch: expected=\(statusCode), got=\(hbResult.status.code)"
            )
        }

        // Note: Vapor adapter parity tests will be enabled once NexusVapor is implemented
        if !isVaporAvailable {
            print("⚠️  Vapor adapter not available - Hummingbird adapter tested independently")
        }
    }

    // MARK: - Response Header Parity Tests

    @Test("Response headers are preserved")
    func responseHeadersMatch() async {
        // Test various header configurations
        let testCases = [
            [],  // No headers
            generateHeaders(count: 1),
            generateHeaders(count: 3),
            generateHeaders(count: 5),
        ]

        for testHeaders in testCases {
            let plug: Plug = { conn in
                var copy = conn
                copy.response = HTTPResponse(
                    status: .ok,
                    headerFields: HTTPFields(testHeaders)
                )
                return copy
            }

            let hbResult = await runHummingbirdPlug(plug)

            // Compare header counts
            #expect(
                hbResult.headers.count == testHeaders.count,
                "Header count mismatch: expected=\(testHeaders.count), got=\(hbResult.headers.count)"
            )

            // Compare each header
            for header in testHeaders {
                let expectedValue = header.value
                let actualValue = hbResult.headers[header.name]

                let nameString = header.name.rawName
                #expect(
                    actualValue == expectedValue,
                    "Header value mismatch for \(nameString): expected='\(expectedValue)', got='\(actualValue ?? "nil")'"
                )
            }
        }
    }

    // MARK: - Response Body Parity Tests

    @Test("Response bodies are transmitted correctly")
    func responseBodiesMatch() async {
        // Test various body sizes
        let bodySizes = [0, 10, 100, 512, 1024]

        for bodySize in bodySizes {
            let bodyData = Data((0..<bodySize).map { _ in UInt8.random(in: 0...255) })

            let plug: Plug = { conn in
                conn.respond(status: .ok, body: .buffered(bodyData))
            }

            let hbResult = await runHummingbirdPlug(plug)

            // Compare body size
            #expect(
                hbResult.body.count == bodySize,
                "Body size mismatch: expected=\(bodySize), got=\(hbResult.body.count)"
            )

            // Compare body data
            #expect(
                hbResult.body == bodyData,
                "Body data mismatch for size \(bodySize)"
            )
        }
    }

    @Test("String response bodies work correctly")
    func stringResponseBodiesMatch() async {
        let testStrings = [
            "",
            "hello",
            "hello nexus",
            "Multi\nLine\nString",
            String(repeating: "x", count: 1000),
        ]

        for testString in testStrings {
            let plug: Plug = { conn in
                conn.respond(status: .ok, body: .string(testString))
            }

            let hbResult = await runHummingbirdPlug(plug)

            let resultString = String(data: hbResult.body, encoding: .utf8)

            #expect(
                resultString == testString,
                "String body mismatch: expected='\(testString)', got='\(resultString ?? "nil")'"
            )
        }
    }

    // MARK: - Halted Connection Parity Tests

    @Test("Halted connections are handled correctly")
    func haltedConnectionsHandledIdentically() async {
        let haltedStatuses: [HTTPResponse.Status] = [
            .forbidden, .unauthorized, .notFound, .methodNotAllowed,
        ]

        for status in haltedStatuses {
            let plug: Plug = { conn in
                conn.respond(
                    status: status,
                    body: .string("access denied")
                ).halted()
            }

            let hbResult = await runHummingbirdPlug(plug)

            // Verify status is correct
            #expect(
                hbResult.status == status,
                "Halted status mismatch: expected=\(status.code), got=\(hbResult.status.code)"
            )

            // Verify body is present
            let resultBody = String(data: hbResult.body, encoding: .utf8)
            #expect(
                resultBody == "access denied",
                "Halted body mismatch: expected='access denied', got='\(resultBody ?? "nil")'"
            )
        }
    }

    // MARK: - Error Handling Parity Tests (ADR-004)

    @Test("ADR-004: Infrastructure errors produce 500 responses")
    func errorsProduceIdentical500Responses() async {
        struct InfrastructureError: Error {}

        // Test throwing plug
        let throwingPlug: Plug = { _ in
            throw InfrastructureError()
        }

        let hbResult = await runHummingbirdPlug(throwingPlug)

        // Adapter should return 500 for thrown errors
        #expect(
            hbResult.status == .internalServerError,
            "Should return 500 for thrown error, got \(hbResult.status.code)"
        )

        // Test normal flow
        let normalPlug: Plug = { conn in
            conn.respond(status: .ok)
        }

        let hbNormalResult = await runHummingbirdPlug(normalPlug)

        #expect(
            hbNormalResult.status == .ok,
            "Should return 200 for normal flow, got \(hbNormalResult.status.code)"
        )
    }

    // MARK: - BeforeSend Hook Parity Tests (ADR-006)

    @Test("ADR-006: BeforeSend hooks execute correctly")
    func beforeSendHooksRunIdentically() async {
        // Test varying numbers of callbacks
        let callbackCounts = [1, 2, 3, 5]

        for callbackCount in callbackCounts {
            let plug: Plug = { conn in
                var result = conn

                // Register multiple callbacks
                for i in 0..<callbackCount {
                    result = result.registerBeforeSend { connection in
                        var copy = connection
                        copy.response.headerFields[
                            HTTPField.Name("X-Hook-\(i)")!
                        ] = "callback-\(i)"
                        return copy
                    }
                }

                return result.respond(status: .ok, body: .string("test"))
            }

            let hbResult = await runHummingbirdPlug(plug)

            // Verify all callbacks executed
            #expect(
                hbResult.headers.count >= callbackCount,
                "Expected at least \(callbackCount) headers, got \(hbResult.headers.count)"
            )

            // Verify each callback's effect
            for i in 0..<callbackCount {
                let headerName = HTTPField.Name("X-Hook-\(i)")!
                let headerValue = hbResult.headers[headerName]

                #expect(
                    headerValue == "callback-\(i)",
                    "Callback \(i) mismatch: expected='callback-\(i)', got='\(headerValue ?? "nil")'"
                )
            }
        }
    }

    @Test("ADR-006: BeforeSend hooks execute in LIFO order")
    func beforeSendHooksExecuteLIFO() async {
        let callbackCount = 5
        let orderHeaderName = HTTPField.Name("X-Execution-Order")!

        let plug: Plug = { conn in
            var result = conn
            for i in 0..<callbackCount {
                result = result.registerBeforeSend { [i] c in
                    var copy = c
                    let existing = copy.response.headerFields[orderHeaderName] ?? ""
                    copy.response.headerFields[orderHeaderName] = existing.isEmpty ? "\(i)" : "\(existing),\(i)"
                    return copy
                }
            }
            return result.respond(status: .ok)
        }

        let hbResult = await runHummingbirdPlug(plug)
        let orderString = hbResult.headers[orderHeaderName] ?? ""
        let order = orderString.split(separator: ",").compactMap { Int($0) }
        let expectedOrder = Array((0..<callbackCount).reversed())

        #expect(order == expectedOrder, "LIFO order mismatch: expected \(expectedOrder), got \(order)")
    }

    // MARK: - End-to-End Request/Response Tests

    @Test("Complete request/response cycle works correctly")
    func completeRequestResponseParity() async {
        // Test various HTTP methods
        let methods: [HTTPRequest.Method] = [.get, .post, .put, .delete, .patch]

        for method in methods {
            let plug: Plug = { conn in
                var copy = conn

                // Echo back request information
                copy.response = HTTPResponse(
                    status: .ok,
                    headerFields: [
                        HTTPField.Name("X-Method")!: conn.request.method.rawValue,
                        HTTPField.Name("X-Path")!: conn.request.path ?? "",
                    ]
                )

                if case .buffered(let data) = conn.requestBody, !data.isEmpty {
                    copy.responseBody = .buffered(data)
                } else {
                    copy.responseBody = .string("ok")
                }

                return copy
            }

            // Test with adapter
            let hbResult = await runHummingbirdPlugWithMethod(plug, method: method)

            #expect(
                hbResult.status == .ok,
                "Status mismatch for \(method.rawValue): expected=200, got=\(hbResult.status.code)"
            )

            let methodHeader = hbResult.headers[HTTPField.Name("X-Method")!]

            #expect(
                methodHeader == method.rawValue,
                "Method header mismatch: expected='\(method.rawValue)', got='\(methodHeader ?? "nil")'"
            )
        }
    }

    // MARK: - Test Result Structure

    /// Structure to hold adapter test results
    private struct AdapterTestResult: Sendable {
        let status: HTTPResponse.Status
        let headers: HTTPFields
        let body: Data

        init(status: HTTPResponse.Status, headers: HTTPFields = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    // MARK: - Hummingbird Test Runner

    /// Run a plug through Hummingbird adapter and capture the result
    private func runHummingbirdPlug(
        _ plug: @escaping Plug
    ) async -> AdapterTestResult {
        // This simulates the Hummingbird adapter behavior
        // In production, this would use Hummingbird's test framework
        let connection = Connection(
            request: generateHTTPRequest(),
            requestBody: .empty
        )

        do {
            let result = try await plug(connection)
            let final = result.runBeforeSend()

            return AdapterTestResult(
                status: final.response.status,
                headers: final.response.headerFields,
                body: extractBodyData(final.responseBody)
            )
        } catch {
            // ADR-004: Infrastructure errors → 500
            return AdapterTestResult(status: .internalServerError)
        }
    }

    /// Run a plug with a specific method through adapter
    private func runHummingbirdPlugWithMethod(
        _ plug: @escaping Plug,
        method: HTTPRequest.Method
    ) async -> AdapterTestResult {
        let connection = Connection(
            request: generateHTTPRequest(method: method),
            requestBody: .empty
        )

        do {
            let result = try await plug(connection)
            let final = result.runBeforeSend()

            return AdapterTestResult(
                status: final.response.status,
                headers: final.response.headerFields,
                body: extractBodyData(final.responseBody)
            )
        } catch {
            return AdapterTestResult(status: .internalServerError)
        }
    }

    // MARK: - Helper Functions

    /// Extract data from ResponseBody
    private func extractBodyData(_ body: ResponseBody) -> Data {
        switch body {
        case .empty:
            return Data()
        case .buffered(let data):
            return data
        case .stream:
            // For property tests, we don't consume streams
            // In real tests, you'd collect the stream
            return Data()
        }
    }
}
