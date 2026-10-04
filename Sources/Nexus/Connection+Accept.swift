import HTTPTypes

// MARK: - Content Negotiation

extension Connection {

    /// Returns `true` if the client's `Accept` header indicates it accepts
    /// the given MIME type (or `*/*`).
    ///
    /// - Parameter mimeType: The MIME type to check, e.g. `"text/html"`.
    public func accepts(_ mimeType: String) -> Bool {
        guard let accept = getReqHeader(.accept) else { return true }
        guard !accept.isEmpty else { return true }
        return (MediaPreferences(accept).preference(for: mimeType)?.quality ?? 0) > 0
    }

    /// Returns `true` if the client prefers HTML over JSON.
    ///
    /// Uses quality values, media-range specificity, and then client declaration
    /// order. HTML is the fallback when neither representation is acceptable;
    /// use `ContentNegotiation` when the pipeline must return 406 instead.
    public var prefersHTML: Bool {
        guard let accept = getReqHeader(.accept) else { return true }
        return MediaPreferences(accept).bestMatch(in: ["text/html", "application/json"]) != "application/json"
    }

    /// Responds with HTML or JSON depending on what the client prefers.
    ///
    /// Mirrors Rails' `respond_to` pattern. Browsers receive the HTML variant;
    /// API clients receive the JSON variant.
    ///
    /// ```swift
    /// GET("/donuts") { conn in
    ///     let donuts = try await Donut.all(db: db)
    ///     return try conn.respondTo(
    ///         html: { renderDonutList(conn: conn, donuts: donuts) },
    ///         json: { try conn.json(value: donuts) }
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - html: Closure that builds the HTML response.
    ///   - json: Closure that builds the JSON response (may throw).
    /// - Returns: Whichever response the client prefers.
    public func respondTo(
        html: () throws -> Connection,
        json: () throws -> Connection
    ) throws -> Connection {
        prefersHTML ? try html() : try json()
    }
}
