import Foundation

// MARK: - Form Parameters

extension Connection {

    /// Form parameters parsed from a URL-encoded request body.
    ///
    /// Decodes an `application/x-www-form-urlencoded` body using the same
    /// split-and-decode algorithm as ``queryParams``, with the addition of
    /// `+`-as-space decoding per the HTML specification.
    ///
    /// For duplicate keys the last value wins, matching Elixir Plug's
    /// `fetch_query_params` semantics.
    ///
    /// Returns an empty dictionary when the request body is `.empty` or
    /// `.stream` (only `.buffered` bodies are parsed).
    public var formParams: [String: String] {
        guard case .buffered(let data) = requestBody,
              let body = String(data: data, encoding: .utf8) else {
            return [:]
        }
        return parseURLEncoded(body, decodePlus: true)
    }
}
