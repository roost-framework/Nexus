import HTTPTypes

// MARK: - Header Helpers

extension Connection {

    /// Returns a copy with the given response header set.
    ///
    /// - Parameters:
    ///   - name: The header field name.
    ///   - value: The header value.
    /// - Returns: A new connection with the header set.
    public func putRespHeader(_ name: HTTPField.Name, _ value: String) -> Connection {
        var copy = self
        copy.response.headerFields[name] = value
        return copy
    }

    /// Returns a copy with the given response header removed.
    ///
    /// - Parameter name: The header field name to remove.
    /// - Returns: A new connection without the header.
    public func deleteRespHeader(_ name: HTTPField.Name) -> Connection {
        var copy = self
        copy.response.headerFields[name] = nil
        return copy
    }

    /// Returns the value of a request header, or `nil` if not present.
    ///
    /// - Parameter name: The header field name.
    /// - Returns: The header value, or `nil`.
    public func getReqHeader(_ name: HTTPField.Name) -> String? {
        request.headerFields[name]
    }

    /// Returns the value of a response header, or `nil` if not present.
    ///
    /// - Parameter name: The header field name.
    /// - Returns: The header value, or `nil`.
    public func getRespHeader(_ name: HTTPField.Name) -> String? {
        response.headerFields[name]
    }

    /// Returns a copy with the given request header set.
    ///
    /// Useful for injecting forwarding headers before calling a downstream
    /// service (e.g., `X-Forwarded-For`).
    ///
    /// - Parameters:
    ///   - name: The header field name.
    ///   - value: The header value.
    /// - Returns: A new connection with the request header set.
    public func putReqHeader(_ name: HTTPField.Name, _ value: String) -> Connection {
        var copy = self
        copy.request.headerFields[name] = value
        return copy
    }

    /// Returns a copy with the given request header removed.
    ///
    /// - Parameter name: The header field name to remove.
    /// - Returns: A new connection without the request header.
    public func deleteReqHeader(_ name: HTTPField.Name) -> Connection {
        var copy = self
        copy.request.headerFields[name] = nil
        return copy
    }

    // MARK: - String-based Header Overloads

    /// Returns a copy with the given response header set.
    ///
    /// If `name` is not a valid HTTP header name the connection is returned
    /// unchanged.
    ///
    /// - Parameters:
    ///   - name: The header field name string (e.g., `"X-Custom-Header"`).
    ///   - value: The header value.
    /// - Returns: A new connection with the header set.
    public func putRespHeader(_ name: String, _ value: String) -> Connection {
        guard let field = HTTPField.Name(name) else { return self }
        return putRespHeader(field, value)
    }

    /// Returns a copy with the given response header removed.
    ///
    /// If `name` is not a valid HTTP header name the connection is returned
    /// unchanged.
    ///
    /// - Parameter name: The header field name string.
    /// - Returns: A new connection without the response header.
    public func deleteRespHeader(_ name: String) -> Connection {
        guard let field = HTTPField.Name(name) else { return self }
        return deleteRespHeader(field)
    }

    /// Returns the value of a response header by name string, or `nil` if absent.
    ///
    /// - Parameter name: The header field name string (case-insensitive).
    /// - Returns: The header value, or `nil`.
    public func getRespHeader(_ name: String) -> String? {
        guard let field = HTTPField.Name(name) else { return nil }
        return getRespHeader(field)
    }

    /// Returns a copy with the given request header set.
    ///
    /// If `name` is not a valid HTTP header name the connection is returned
    /// unchanged.
    ///
    /// - Parameters:
    ///   - name: The header field name string.
    ///   - value: The header value.
    /// - Returns: A new connection with the request header set.
    public func putReqHeader(_ name: String, _ value: String) -> Connection {
        guard let field = HTTPField.Name(name) else { return self }
        return putReqHeader(field, value)
    }

    /// Returns a copy with the given request header removed.
    ///
    /// If `name` is not a valid HTTP header name the connection is returned
    /// unchanged.
    ///
    /// - Parameter name: The header field name string.
    /// - Returns: A new connection without the request header.
    public func deleteReqHeader(_ name: String) -> Connection {
        guard let field = HTTPField.Name(name) else { return self }
        return deleteReqHeader(field)
    }

    /// Returns the value of a request header by name string, or `nil` if absent.
    ///
    /// - Parameter name: The header field name string (case-insensitive).
    /// - Returns: The header value, or `nil`.
    public func getReqHeader(_ name: String) -> String? {
        guard let field = HTTPField.Name(name) else { return nil }
        return getReqHeader(field)
    }

    /// Returns a copy with the `Content-Type` response header set.
    ///
    /// - Parameter contentType: The content type string (e.g., `"text/html"`).
    /// - Returns: A new connection with the content type set.
    public func putRespContentType(_ contentType: String) -> Connection {
        putRespHeader(.contentType, contentType)
    }

    /// Returns all values for the given request header name.
    ///
    /// HTTP allows multiple fields with the same name (e.g., multiple
    /// `Accept-Language` values). This returns every value in declaration order.
    /// Returns an empty array when the header is absent.
    ///
    /// - Parameter name: The header field name.
    /// - Returns: All values for the header, or an empty array.
    public func getReqHeaders(_ name: HTTPField.Name) -> [String] {
        request.headerFields[values: name]
    }

    /// Returns all values for the given request header name string.
    ///
    /// - Parameter name: The header field name string (case-insensitive).
    /// - Returns: All values for the header, or an empty array.
    public func getReqHeaders(_ name: String) -> [String] {
        guard let field = HTTPField.Name(name) else { return [] }
        return getReqHeaders(field)
    }

    /// Returns all values for the given response header name.
    ///
    /// - Parameter name: The header field name.
    /// - Returns: All values for the header, or an empty array.
    public func getRespHeaders(_ name: HTTPField.Name) -> [String] {
        response.headerFields[values: name]
    }

    /// Returns all values for the given response header name string.
    ///
    /// - Parameter name: The header field name string (case-insensitive).
    /// - Returns: All values for the header, or an empty array.
    public func getRespHeaders(_ name: String) -> [String] {
        guard let field = HTTPField.Name(name) else { return [] }
        return getRespHeaders(field)
    }
}

// MARK: - Status

extension Connection {

    /// Returns a copy with the response status set, without halting.
    ///
    /// Unlike ``respond(status:body:)`` which also sets the body and halts,
    /// this method only changes the status code.
    ///
    /// - Parameter status: The HTTP response status.
    /// - Returns: A new connection with the updated status.
    public func putStatus(_ status: HTTPResponse.Status) -> Connection {
        var copy = self
        copy.response.status = status
        return copy
    }
}

// MARK: - Assigns

extension Connection {

    /// Returns a copy with `other` merged into `assigns`.
    ///
    /// Keys in `other` overwrite existing keys in `assigns`. Keys absent from
    /// `other` are left unchanged.
    ///
    /// - Parameter other: The assigns to merge in.
    /// - Returns: A new connection with the merged assigns.
    public func mergeAssigns(_ other: [String: any Sendable]) -> Connection {
        var copy = self
        for (key, value) in other {
            copy.assigns[key] = value
        }
        return copy
    }
}
