import Foundation
import HTTPTypes

/// The set of content types the ``bodyParser(_:)`` plug will parse.
public enum BodyParserType: Sendable, Hashable {
    /// Parse `application/json` bodies into ``ParsedJSONKey``.
    case json
    /// Parse `application/x-www-form-urlencoded` bodies into ``BodyParamsKey``.
    case urlEncoded
    /// Parse `multipart/form-data` bodies into ``BodyParamsKey`` and ``UploadedFilesKey``.
    case multipart
}

/// Configuration for the ``bodyParser(_:)`` plug.
public struct BodyParserConfig: Sendable {

    /// Content types to parse. Defaults to all supported types.
    public var parsers: Set<BodyParserType>

    /// Maximum body size in bytes before the parser rejects with 413.
    /// Defaults to `nil` (no additional limit beyond the adapter's).
    public var maxBodySize: Int?

    /// Creates a body parser configuration.
    ///
    /// - Parameters:
    ///   - parsers: The content types to parse. Defaults to JSON, URL-encoded, and multipart.
    ///   - maxBodySize: Optional size limit. Bodies exceeding this are rejected with 413.
    public init(
        parsers: Set<BodyParserType> = [.json, .urlEncoded, .multipart],
        maxBodySize: Int? = nil
    ) {
        self.parsers = parsers
        self.maxBodySize = maxBodySize
    }
}

/// Creates a plug that automatically parses the request body based on
/// `Content-Type` and stores the result in typed assigns.
///
/// This is the Nexus equivalent of Elixir's `Plug.Parsers`. Add it
/// early in the pipeline so route handlers can read parsed data from
/// assigns without choosing a parser:
///
/// ```swift
/// let app = pipeline([
///     bodyParser(),
///     router.callAsFunction,
/// ])
///
/// POST("/submit") { conn in
///     let name = conn.bodyParams["name"]       // from form or multipart
///     let file = conn.uploadedFile("doc")       // from multipart
///     let json = conn.parsedJSON                // from JSON
///     // ...
/// }
/// ```
///
/// | Content-Type | Assigns populated |
/// |---|---|
/// | `application/json` | ``ParsedJSONKey`` |
/// | `application/x-www-form-urlencoded` | ``BodyParamsKey`` |
/// | `multipart/form-data` | ``BodyParamsKey`` + ``UploadedFilesKey`` |
///
/// - Parameter config: Parser configuration. Defaults to parsing all types.
/// - Returns: A plug that parses request bodies by Content-Type.
public func bodyParser(_ config: BodyParserConfig = .init()) -> Plug {
    { conn in
        // Only parse methods that typically carry a body
        let method = conn.request.method
        guard method == .post || method == .put || method == .patch else {
            return conn
        }

        // Must have a buffered body
        guard case .buffered(let data) = conn.requestBody else {
            return conn
        }

        // Check size limit
        if let maxSize = config.maxBodySize, data.count > maxSize {
            return conn.respond(
                status: .contentTooLarge,
                body: .string("Payload Too Large")
            )
        }

        // Don't re-parse if already parsed (idempotent)
        if conn[BodyParamsKey.self] != nil || conn[ParsedJSONKey.self] != nil {
            return conn
        }

        guard let contentType = conn.request.headerFields[.contentType]?.lowercased() else {
            return conn
        }

        // JSON
        if contentType.contains("application/json"), config.parsers.contains(.json) {
            if let parsed = try? JSONSerialization.jsonObject(with: data) {
                return conn.assign(ParsedJSONKey.self, value: JSONValue(parsed))
            }
            return conn
        }

        // URL-encoded form
        if contentType.contains("application/x-www-form-urlencoded"),
           config.parsers.contains(.urlEncoded) {
            if let body = String(data: data, encoding: .utf8) {
                let params = parseURLEncoded(body, decodePlus: true)
                return conn.assign(BodyParamsKey.self, value: params)
            }
            return conn
        }

        // Multipart
        if contentType.contains("multipart/form-data"), config.parsers.contains(.multipart) {
            let fullContentType = conn.request.headerFields[.contentType] ?? ""
            guard let boundary = MultipartParser.extractBoundary(from: fullContentType) else {
                return conn
            }
            if let result = try? MultipartParser.parse(data: data, boundary: boundary) {
                var updated = conn.assign(BodyParamsKey.self, value: result.fields)
                updated = updated.assign(UploadedFilesKey.self, value: result.files)
                return updated
            }
            return conn
        }

        return conn
    }
}
