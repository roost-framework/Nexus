import Foundation
import Testing

@testable import SwiftCheck

/// Property test helpers that bridge SwiftCheck with Swift Testing framework.
///
/// This module provides utilities for writing property-based tests using SwiftCheck
/// within the Swift Testing framework, enabling randomized testing with shrunk failures.
///
/// # Example Usage
/// ```swift
/// @Suite("MyProperties")
/// struct MyProperties {
///     @Test("array reversal property")
///     func arrayReversalProperty() {
///         assertProperty(forAll { (xs: [Int]) in
///             xs.reversed().reversed() == xs
///         })
///     }
/// }
/// ```

/// Common generators for Nexus types
extension Gen {
    /// Generate non-empty strings
    public static var nonEmptyString: Gen<String> {
        return String.arbitrary.suchThat { !$0.isEmpty }
    }

    /// Generate valid HTTP method strings
    public static var httpMethod: Gen<String> {
        return Gen<String>.fromElements(of: ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE"])
    }

    /// Generate valid HTTP status codes
    public static var httpStatusCode: Gen<Int> {
        return Gen<Int>.fromElements(of: [200, 201, 204, 301, 302, 400, 401, 403, 404, 500, 502, 503])
    }

    /// Generate HTTP header values (ASCII strings)
    public static var httpHeaderValue: Gen<String> {
        return String.arbitrary.suchThat { str in
            str.allSatisfy { $0.isASCII }
        }
    }

    /// Generate data chunks for streaming
    public static func dataChunk(maxSize: Int = 1024) -> Gen<Data> {
        return Gen<Int>.choose((0, maxSize)).map { size in
            Data((0..<size).map { _ in UInt8.random(in: 0...255) })
        }
    }
}

/// Custom test configuration for property-based tests
public struct PropertyTestConfig: Sendable {
    public let maxTestCases: Int
    public let maxDiscardedTestCases: Int
    public let verbose: Bool

    public static let `default` = PropertyTestConfig(
        maxTestCases: 100,
        maxDiscardedTestCases: 1000,
        verbose: false
    )

    public static let thorough = PropertyTestConfig(
        maxTestCases: 1000,
        maxDiscardedTestCases: 1000,
        verbose: true
    )

    public static let quick = PropertyTestConfig(
        maxTestCases: 50,
        maxDiscardedTestCases: 100,
        verbose: false
    )
}

/// Assert that a property holds for all generated inputs
///
/// - Parameters:
///   - property: SwiftCheck property to test
///   - config: Successful-case and discard limits, plus verbose output control.
///   - sourceLocation: Call site for failure reporting.
public func assertProperty(
    _ property: Property,
    config: PropertyTestConfig = .default,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    // SwiftCheck 0.12's public assertion API uses XCTest. Its result API is internal;
    // keep test-only access here so every unsuccessful outcome becomes a Swift Testing issue.
    let arguments = CheckerArguments(
        maxAllowableSuccessfulTests: config.maxTestCases,
        maxAllowableDiscardedTests: config.maxDiscardedTestCases
    )
    let result = quickCheckWithResult(arguments, config.verbose ? property.verbose : property)
    if case .success = result { return }
    Issue.record("SwiftCheck did not succeed: \(String(describing: result))", sourceLocation: sourceLocation)
}
