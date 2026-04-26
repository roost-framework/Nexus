import Foundation
import SwiftCheck
import HTTPTypes

// MARK: - HTTP Method Generators

extension HTTPRequest.Method: @retroactive Arbitrary {
    /// Generate arbitrary HTTP methods for property-based testing
    public static var arbitrary: Gen<HTTPRequest.Method> {
        return Gen<HTTPRequest.Method>.fromElements(of: [
            .get,
            .post,
            .put,
            .delete,
            .patch,
            .head,
            .options,
            .trace,
            .connect,
        ])
    }
}

// MARK: - HTTP Header Generators

extension HTTPField: @retroactive Arbitrary {
    public static var arbitrary: Gen<HTTPField> {
        arbitraryName.flatMap { name in
            arbitraryValue.map { value in
                HTTPField(name: HTTPField.Name(name)!, value: value)
            }
        }
    }

    /// Generate valid HTTP header names
    ///
    /// Generates common HTTP headers like "content-type", "authorization", etc.
    public static var arbitraryName: Gen<String> {
        return Gen<String>.fromElements(of: [
            "content-type",
            "authorization",
            "accept",
            "accept-encoding",
            "user-agent",
            "host",
            "connection",
            "content-length",
            "cache-control",
            "referer",
            "origin",
            "access-control-request-method",
            "access-control-request-headers",
        ])
    }

    /// Generate valid HTTP header values (ASCII strings)
    ///
    /// HTTP header values must be ASCII characters per RFC 7230
    public static var arbitraryValue: Gen<String> {
        return Gen<String>.fromElements(of: [
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "-", "/", "_", ":", ";", ".", ",", "=", "+", " "
        ])
    }

}

// MARK: - HTTP Request Path Generators

extension Gen {
    /// Generate valid HTTP request paths
    ///
    /// Generates paths like "/", "/users", "/posts/123", etc.
    public static var httpPath: Gen<String> {
        return Gen<Int>.choose((0, 5)).flatMap { segmentCount in
            guard segmentCount > 0 else {
                return Gen<String>.pure("/")
            }

            // Generate segments
            let segmentChars = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
                                "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_"]
            let segmentGen: Gen<String> = Gen<String>.fromElements(of: segmentChars)
                .suchThat { !$0.isEmpty }

            // Generate array of segments and join
            let segmentsGen = Gen<Int>.choose((0, segmentCount)).map { count in
                Array(repeating: "segment", count: count)
            }

            return segmentsGen.map { segments in
                "/" + segments.joined(separator: "/")
            }
        }
    }

    /// Generate HTTP query strings
    ///
    /// Generates query strings like "?key=value&foo=bar"
    public static var httpQueryString: Gen<String> {
        return Gen<Int>.choose((0, 3)).flatMap { paramCount in
            guard paramCount > 0 else {
                return Gen<String>.pure("")
            }

            let keyChars = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
            let valueChars = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
                             "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
            let paramGen: Gen<String> = Gen<String>.fromElements(of: keyChars)
                .flatMap { key in
                    Gen<String>.fromElements(of: valueChars)
                        .map { value in
                            "\(key)=\(value)"
                        }
                }

            let paramsGen = Gen<Int>.choose((0, paramCount)).map { count in
                Array(repeating: "key=value", count: count)
            }

            return paramsGen.map { params in
                "?" + params.joined(separator: "&")
            }
        }
    }
}

// MARK: - HTTP Request Body Generators

extension Gen {
    /// Generate request body data (empty or buffered)
    ///
    /// Generates small data chunks suitable for property-based testing
    public static var requestBody: Gen<Data> {
        return Gen<Int>.choose((0, 1024)).flatMap { size in
            guard size > 0 else {
                return Gen<Data>.pure(Data())
            }

            return Gen<Int>.choose((0, 1024)).map { size in
                Data((0..<size).map { _ in UInt8.random(in: 0...255) })
            }
        }
    }
}

// MARK: - HTTP Request Generators

extension HTTPRequest: @retroactive Arbitrary {
    /// Generate arbitrary HTTP requests for property-based testing
    ///
    /// This generator creates complete HTTPRequest objects with:
    /// - Random HTTP method (GET, POST, PUT, DELETE, etc.)
    /// - Valid scheme (http or https)
    /// - Non-empty authority
    /// - Valid path with 0-5 segments
    /// - 0-5 random headers
    public static var arbitrary: Gen<HTTPRequest> {
        return HTTPRequest.Method.arbitrary.flatMap { method in
            Gen<String>.fromElements(of: ["http", "https"]).flatMap { scheme in
                String.arbitrary.suchThat { !$0.isEmpty }.flatMap { authority in
                    Gen<String>.httpPath.flatMap { path in
                        // Generate 0-5 headers
                        Gen<Int>.choose((0, 5)).flatMap { headerCount in
                            let headers = (0..<headerCount).map { _ in
                                HTTPField(name: .contentType, value: "text/plain")
                            }

                            var request = HTTPRequest(
                                method: method,
                                scheme: scheme,
                                authority: authority,
                                path: path
                            )

                            // Add headers
                            for header in headers {
                                request.headerFields[header.name] = header.value
                            }

                            return Gen.pure(request)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Connection Arbitrary Conformance

import struct Nexus.Connection

extension Connection: Arbitrary {
    /// Generate arbitrary Connection values for property-based testing
    ///
    /// This generator creates Connection objects with random HTTP requests
    /// and default response/state values.
    public static var arbitrary: Gen<Connection> {
        return HTTPRequest.arbitrary.map { request in
            Connection(request: request)
        }
    }
}
