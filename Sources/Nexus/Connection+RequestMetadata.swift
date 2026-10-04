import HTTPTypes

extension Connection {
    /// The hostname or IPv6 address, without brackets or an explicit port.
    /// Returns `nil` when the request has no authority.
    public var host: String? { authorityParts?.host }

    /// The URL scheme of the request (for example, `"https"`).
    public var scheme: String? { request.scheme }

    /// The explicit port, or 80/443 for HTTP/HTTPS when no port is specified.
    /// Invalid explicit ports and unknown schemes without a port return `nil`.
    public var port: Int? {
        if let parts = authorityParts, parts.hasPort { return parts.port }
        switch scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    /// The request path without its query string, preserving escaped characters.
    public var requestPath: String {
        String((request.path ?? "/").split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }

    /// The raw query string without the leading question mark.
    public var queryString: String {
        guard let path = request.path, let start = path.firstIndex(of: "?") else { return "" }
        return String(path[path.index(after: start)...])
    }

    /// Non-empty segments of the request path, still percent-encoded.
    public var pathInfo: [String] { requestPath.split(separator: "/").map(String.init) }

    /// The full request URL, preserving the escaped path and query string.
    /// Default HTTP/HTTPS ports are omitted and IPv6 addresses are bracketed.
    /// Missing components default to `http`, `localhost`, and `/`.
    public var requestURL: String {
        let scheme = (scheme ?? "http").lowercased()
        let host = host ?? "localhost"
        let authority = host.contains(":") ? "[\(host)]" : host
        let port = authorityParts?.port
        let defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : nil)
        let suffix = port.flatMap { $0 == defaultPort ? nil : ":\($0)" } ?? ""
        let path = request.path.flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        return "\(scheme)://\(authority)\(suffix)\(path)"
    }

    private var authorityParts: (host: String, port: Int?, hasPort: Bool)? {
        guard let authority = request.authority else { return nil }
        let host: String
        let suffix: Substring
        if authority.hasPrefix("["), let end = authority.firstIndex(of: "]") {
            host = String(authority[authority.index(after: authority.startIndex)..<end])
            suffix = authority[authority.index(after: end)...]
        } else if authority.filter({ $0 == ":" }).count == 1,
            let colon = authority.firstIndex(of: ":")
        {
            host = String(authority[..<colon])
            suffix = authority[colon...]
        } else {
            return (authority, nil, false)
        }
        guard !suffix.isEmpty else { return (host, nil, false) }
        let digits = suffix.dropFirst()
        guard suffix.first == ":", !digits.isEmpty,
            digits.utf8.allSatisfy({ (48...57).contains($0) }),
            let port = Int(digits), (0...65535).contains(port)
        else {
            return (host, nil, true)
        }
        return (host, port, true)
    }
}
