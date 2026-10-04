import HTTPTypes

// MARK: - ContentNegotiation Plug

/// A plug that performs HTTP content negotiation against an `Accept` header.
///
/// Compares the client's `Accept` header against the server's list of
/// supported MIME types (respecting quality values). Returns
/// `406 Not Acceptable` when no supported type is acceptable to the client.
///
/// On success, the negotiated MIME type is stored in the connection assigns
/// under ``NegotiatedTypeKey``:
///
/// ```swift
/// let negotiation = ContentNegotiation(supported: ["application/json", "text/html"])
/// let app = pipeline([negotiation, router])
///
/// // In a handler:
/// let mime = conn[ContentNegotiation.NegotiatedTypeKey.self]  // "application/json"
/// ```
public struct ContentNegotiation: Sendable {

    /// The assign key for the negotiated MIME type.
    ///
    /// Read from within a downstream plug or handler after the
    /// `ContentNegotiation` plug has run:
    ///
    /// ```swift
    /// if let mime = conn[ContentNegotiation.NegotiatedTypeKey.self] {
    ///     // Set response Content-Type accordingly
    /// }
    /// ```
    public enum NegotiatedTypeKey: AssignKey {
        /// The selected MIME type.
        public typealias Value = String
    }

    private let supported: [String]
    private let defaultType: String?

    /// Creates a `ContentNegotiation` plug.
    ///
    /// - Parameters:
    ///   - supported: Ordered list of MIME types the server can produce
    ///     (e.g., `["application/json", "text/html"]`). Client quality and
    ///     specificity take precedence; server order breaks remaining ties.
    ///   - defaultType: MIME type to use when no `Accept` header is present.
    ///     Defaults to the first element of `supported`.
    public init(supported: [String], defaultType: String? = nil) {
        self.supported = supported
        self.defaultType = defaultType
    }
}

extension ContentNegotiation: ModulePlug {

    /// Negotiates content type and stores the result in assigns.
    ///
    /// - Parameter connection: The incoming connection.
    /// - Returns: The connection with the negotiated type in assigns, or a
    ///   halted `406 Not Acceptable` response if no match is found.
    public func call(_ connection: Connection) async throws -> Connection {
        let connection = connection.varying(on: "Accept")
        let acceptHeader = connection.request.headerFields[.accept]

        guard let accept = acceptHeader, !accept.isEmpty else {
            if let chosen = defaultType ?? supported.first {
                return connection.assign(NegotiatedTypeKey.self, value: chosen)
            }
            return connection.respond(status: .notAcceptable)
        }

        if let match = MediaPreferences(accept).bestMatch(in: supported) {
            return connection.assign(NegotiatedTypeKey.self, value: match)
        }

        return connection.respond(
            status: .notAcceptable,
            body: .string("Not Acceptable: supported types are \(supported.joined(separator: ", "))")
        )
    }
}
