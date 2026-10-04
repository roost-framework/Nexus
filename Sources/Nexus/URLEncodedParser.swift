/// Parses a URL-encoded string (e.g. `"a=1&b=hello+world"`) into a dictionary.
///
/// Splits on `&`, then splits each pair on `=` (at most once). Both keys and
/// values are percent-decoded. For duplicate keys the last value wins,
/// matching Elixir Plug's `fetch_query_params` semantics.
///
/// - Parameters:
///   - string: The URL-encoded string to parse.
///   - decodePlus: When `true`, `+` is replaced with a space before
///     percent-decoding. Set to `true` for `application/x-www-form-urlencoded`
///     bodies and URL query strings (as in Plug).
/// - Returns: A dictionary of decoded key–value pairs.
func parseURLEncoded(
    _ string: some StringProtocol,
    decodePlus: Bool
) -> [String: String] {
    var params: [String: String] = [:]
    for pair in string.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let key = parts.first else { continue }
        var rawKey = String(key)
        var rawValue: String
        if parts.count > 1 {
            rawValue = String(parts[1])
        } else {
            rawValue = ""
        }
        if decodePlus {
            rawKey = rawKey.replacingOccurrences(of: "+", with: " ")
            rawValue = rawValue.replacingOccurrences(of: "+", with: " ")
        }
        rawKey = rawKey.removingPercentEncoding ?? rawKey
        rawValue = rawValue.removingPercentEncoding ?? rawValue
        params[rawKey] = rawValue
    }
    return params
}
