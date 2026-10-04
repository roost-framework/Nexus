import Foundation

// MARK: - Route Parameters (Enhanced Access)

extension Connection {

    /// Path parameters extracted by the router from the matched route pattern.
    ///
    /// Alias for ``params``, provided for symmetry with ``queryParameters``
    /// and ``parameters``.
    ///
    /// For a route pattern like `/users/:id`, after matching `/users/42` this
    /// returns `["id": "42"]`.
    public var pathParameters: [String: String] {
        params
    }

    /// Query parameters parsed from the request URI, preserving duplicate keys.
    ///
    /// Unlike ``queryParams`` (which returns only the last value for duplicate
    /// keys), `queryParameters` preserves **all** values as an array.
    ///
    /// Both keys and values are percent-decoded.
    ///
    /// ```swift
    /// // Request: GET /items?tag=swift&tag=concurrency
    /// conn.queryParameters["tag"]  // ["swift", "concurrency"]
    /// ```
    public var queryParameters: [String: [String]] {
        guard let path = request.path,
              let queryStart = path.firstIndex(of: "?") else {
            return [:]
        }
        let queryString = String(path[path.index(after: queryStart)...])
        return parseMultiValueQueryString(queryString)
    }

    /// Combined path, body, and query parameters.
    ///
    /// Path parameters take precedence over body parameters, then query parameters.
    /// Each value is wrapped in a single-element array for a uniform interface.
    ///
    /// ```swift
    /// // Route /users/:id, Request GET /users/42?format=json
    /// conn.parameters["id"]      // ["42"]   — from path
    /// conn.parameters["format"]  // ["json"] — from query
    /// ```
    public var parameters: [String: [String]] {
        var combined = queryParameters
        for (key, value) in bodyParams {
            combined[key] = [value]
        }
        for (key, value) in params {
            combined[key] = [value]
        }
        return combined
    }

    /// Returns the first value of the named parameter.
    ///
    /// Checks path parameters, then body parameters, then the first query parameter value.
    ///
    /// - Parameter name: The parameter name.
    /// - Returns: The parameter value, or `nil` if not present.
    public func getParameter(_ name: String) -> String? {
        params[name] ?? bodyParams[name] ?? queryParameters[name]?.first
    }

    /// Returns all values of the named query parameter.
    ///
    /// Returns an empty array when the parameter is absent.
    ///
    /// - Parameter name: The parameter name.
    /// - Returns: All values for the parameter.
    public func getParameters(_ name: String) -> [String] {
        queryParameters[name] ?? []
    }

    /// Returns the named parameter converted to the specified type.
    ///
    /// Checks path parameters first, then query parameters.
    ///
    /// ```swift
    /// // Request: GET /items?page=3
    /// let page: Int = conn.getParameter("page", as: Int.self) ?? 1
    /// ```
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - type: A `LosslessStringConvertible` type to convert to.
    /// - Returns: The converted value, or `nil` if absent or unconvertible.
    public func getParameter<T: LosslessStringConvertible>(_ name: String, as type: T.Type) -> T? {
        guard let raw = getParameter(name) else { return nil }
        return T(raw)
    }
}

// MARK: - Internal Helpers

/// Parses a query string, preserving duplicate keys as arrays.
///
/// - Parameter queryString: The raw query string (without the leading `?`).
/// - Returns: A dictionary mapping parameter names to arrays of values.
private func parseMultiValueQueryString(_ queryString: String) -> [String: [String]] {
    var result: [String: [String]] = [:]
    for pair in queryString.split(separator: "&", omittingEmptySubsequences: true) {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard !parts.isEmpty else { continue }
        let rawKey = String(parts[0]).replacingOccurrences(of: "+", with: " ")
        let rawValue = parts.count > 1 ? String(parts[1]).replacingOccurrences(of: "+", with: " ") : ""
        let key = rawKey.removingPercentEncoding ?? rawKey
        let value = rawValue.removingPercentEncoding ?? rawValue
        result[key, default: []].append(value)
    }
    return result
}
