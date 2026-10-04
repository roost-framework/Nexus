import Foundation
import HTTPTypes

extension Connection {
    /// Merges request headers, replacing existing fields of each supplied name.
    /// When the input repeats a name, its last value wins, as with repeated `putReqHeader` calls.
    /// - Parameter headers: Fields to merge.
    /// - Returns: A new connection with the merged request headers.
    public func mergeReqHeaders(_ headers: HTTPFields) -> Connection {
        var copy = self
        for field in headers { copy.request.headerFields[field.name] = field.value }
        return copy
    }

    /// Merges response headers, replacing existing fields of each supplied name.
    /// Use `prependRespHeaders` to preserve repeated fields such as `Set-Cookie`.
    /// - Parameter headers: Fields to merge.
    /// - Returns: A new connection with the merged response headers.
    public func mergeRespHeaders(_ headers: HTTPFields) -> Connection {
        var copy = self
        for field in headers { copy.response.headerFields[field.name] = field.value }
        return copy
    }

    /// Prepends request headers in their supplied order, preserving existing values.
    /// - Parameter headers: Fields to prepend.
    /// - Returns: A new connection with the combined request headers.
    public func prependReqHeaders(_ headers: HTTPFields) -> Connection {
        var copy = self
        copy.request.headerFields = HTTPFields(Array(headers) + Array(request.headerFields))
        return copy
    }

    /// Prepends response headers in their supplied order, preserving existing values.
    /// - Parameter headers: Fields to prepend.
    /// - Returns: A new connection with the combined response headers.
    public func prependRespHeaders(_ headers: HTTPFields) -> Connection {
        var copy = self
        copy.response.headerFields = HTTPFields(Array(headers) + Array(response.headerFields))
        return copy
    }

    /// Transforms the first matching request field, or inserts `initial` when absent.
    /// The transform is not called for an absent field. Errors propagate without modifying the receiver.
    /// - Parameters:
    ///   - name: The header name to update.
    ///   - initial: The value to insert when no field matches.
    ///   - transform: Computes the replacement for the first matching value.
    /// - Returns: A new connection with the updated request header.
    /// - Throws: Any error thrown by `transform`.
    public func updateReqHeader(
        _ name: HTTPField.Name, initial: String, transform: (String) throws -> String
    ) rethrows -> Connection {
        var copy = self
        if let index = copy.request.headerFields.firstIndex(where: { $0.name == name }) {
            copy.request.headerFields[index].value = try transform(copy.request.headerFields[index].value)
        } else {
            copy.request.headerFields[name] = initial
        }
        return copy
    }

    /// Transforms the first matching response field, or inserts `initial` when absent.
    /// The transform is not called for an absent field. Errors propagate without modifying the receiver.
    /// - Parameters:
    ///   - name: The header name to update.
    ///   - initial: The value to insert when no field matches.
    ///   - transform: Computes the replacement for the first matching value.
    /// - Returns: A new connection with the updated response header.
    /// - Throws: Any error thrown by `transform`.
    public func updateRespHeader(
        _ name: HTTPField.Name, initial: String, transform: (String) throws -> String
    ) rethrows -> Connection {
        var copy = self
        if let index = copy.response.headerFields.firstIndex(where: { $0.name == name }) {
            copy.response.headerFields[index].value = try transform(copy.response.headerFields[index].value)
        } else {
            copy.response.headerFields[name] = initial
        }
        return copy
    }

    /// String overload of `updateReqHeader`; invalid header names leave the connection unchanged.
    /// - Parameters:
    ///   - name: The header name to update.
    ///   - initial: The value to insert when absent.
    ///   - transform: Computes the replacement for the first matching value.
    /// - Returns: A new connection with the updated request header.
    /// - Throws: Any error thrown by `transform`.
    public func updateReqHeader(
        _ name: String, initial: String, transform: (String) throws -> String
    ) rethrows -> Connection {
        guard let name = HTTPField.Name(name) else { return self }
        return try updateReqHeader(name, initial: initial, transform: transform)
    }

    /// String overload of `updateRespHeader`; invalid header names leave the connection unchanged.
    /// - Parameters:
    ///   - name: The header name to update.
    ///   - initial: The value to insert when absent.
    ///   - transform: Computes the replacement for the first matching value.
    /// - Returns: A new connection with the updated response header.
    /// - Throws: Any error thrown by `transform`.
    public func updateRespHeader(
        _ name: String, initial: String, transform: (String) throws -> String
    ) rethrows -> Connection {
        guard let name = HTTPField.Name(name) else { return self }
        return try updateRespHeader(name, initial: initial, transform: transform)
    }

    /// Sets a response content type with an optional charset.
    /// Pass `nil` to omit the charset. The existing one-argument overload keeps its exact-value behavior.
    /// - Parameters:
    ///   - contentType: The response media type.
    ///   - charset: The charset parameter to append, or `nil` to omit it.
    /// - Returns: A new connection with the content type set.
    public func putRespContentType(_ contentType: String, charset: String?) -> Connection {
        putRespContentType(charset.map { "\(contentType); charset=\($0)" } ?? contentType)
    }

    /// Adds a token to Vary without losing existing values or duplicating tokens.
    /// A wildcard Vary already covers every request header and is preserved.
    func varying(on name: String) -> Connection {
        let tokens = getRespHeaders(.vary).flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard !tokens.contains("*"), !tokens.contains(name.lowercased()) else { return self }
        var copy = self
        copy.response.headerFields.append(HTTPField(name: .vary, value: name))
        return copy
    }
}
