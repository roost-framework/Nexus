// MARK: - Query Parameters

extension Connection {

    /// Query parameters parsed from the request URL.
    ///
    /// Parses the query string portion of ``request``'s path on each access.
    /// For duplicate keys, the last value wins (matching Elixir Plug's
    /// `fetch_query_params` semantics). Both keys and values are
    /// percent-decoded.
    ///
    /// Returns an empty dictionary if there is no query string.
    public var queryParams: [String: String] {
        guard let path = request.path,
              let queryStart = path.firstIndex(of: "?") else {
            return [:]
        }
        let queryString = path[path.index(after: queryStart)...]
        return parseURLEncoded(queryString, decodePlus: true)
    }
}
