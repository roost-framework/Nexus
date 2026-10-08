import Foundation
import HTTPTypes

#if canImport(Security)
import Security
#endif

/// Configuration for the CSRF protection plug.
public struct CSRFConfig: Sendable {

    /// The session key where the CSRF token is stored.
    /// Defaults to `"_csrf_token"`.
    public var sessionKey: String

    /// The form parameter name checked for the CSRF token.
    /// Defaults to `"_csrf_token"`.
    public var formParam: String

    /// The HTTP header name checked as a fallback for the CSRF token.
    /// Defaults to `"x-csrf-token"`.
    public var headerName: String

    /// Creates a CSRF configuration.
    ///
    /// - Parameters:
    ///   - sessionKey: The session key for the token. Defaults to `"_csrf_token"`.
    ///   - formParam: The form parameter name. Defaults to `"_csrf_token"`.
    ///   - headerName: The header name. Defaults to `"x-csrf-token"`.
    public init(
        sessionKey: String = "_csrf_token",
        formParam: String = "_csrf_token",
        headerName: String = "x-csrf-token"
    ) {
        self.sessionKey = sessionKey
        self.formParam = formParam
        self.headerName = headerName
    }
}

/// A plug that enforces CSRF (Cross-Site Request Forgery) protection.
///
/// Stores a random token in the session and validates it on
/// state-changing requests (POST, PUT, PATCH, DELETE). The token is
/// accepted from either a form parameter or an HTTP header.
///
/// Safe methods (GET, HEAD, OPTIONS) skip validation but ensure a
/// token exists in the session for later use.
///
/// Requires ``sessionPlug(_:)`` to be earlier in the pipeline.
///
/// ```swift
/// let app = pipeline([
///     sessionPlug(SessionConfig(secret: mySecret)),
///     csrfProtection(),
///     router
/// ])
/// ```
///
/// To embed the token in a response (for forms or JSON APIs), use
/// ``csrfToken(conn:config:)``.
///
/// - Parameter config: The CSRF configuration. Defaults to `CSRFConfig()`.
/// - Returns: A plug that enforces CSRF protection.
public func csrfProtection(_ config: CSRFConfig = CSRFConfig()) -> Plug {
    { conn in
        let method = conn.request.method

        // Safe methods: ensure token exists, skip validation
        if method == .get || method == .head || method == .options {
            let (_, updated) = csrfToken(conn: conn, config: config)
            return updated
        }

        // State-changing methods: validate token
        let storedToken = conn.getSession(config.sessionKey)

        guard let storedToken, !storedToken.isEmpty else {
            return forbidden(conn)
        }

        // Check form parameter first, then header
        let submittedToken: String?
        if let formToken = conn.formParams[config.formParam], !formToken.isEmpty {
            submittedToken = formToken
        } else if let headerName = HTTPField.Name(config.headerName) {
            submittedToken = conn.request.headerFields[headerName]
        } else {
            submittedToken = nil
        }

        guard let submittedToken, constantTimeEqual(submittedToken, storedToken) else {
            return forbidden(conn)
        }

        return conn
    }
}

/// Returns the current CSRF token, generating one if needed.
///
/// Use this to embed the token in HTML forms or return it in JSON
/// responses so the client can include it on subsequent state-changing
/// requests.
///
/// ```swift
/// let (token, conn) = csrfToken(conn: conn)
/// return conn.json(value: ["csrf_token": token])
/// ```
///
/// - Parameters:
///   - conn: The current connection (must have passed through
///     ``sessionPlug(_:)``).
///   - config: The CSRF configuration. Defaults to `CSRFConfig()`.
/// - Returns: A tuple of `(token, connection)`. The connection may have
///   a newly generated token stored in its session.
public func csrfToken(
    conn: Connection,
    config: CSRFConfig = CSRFConfig()
) -> (String, Connection) {
    if let existing = conn.getSession(config.sessionKey), !existing.isEmpty {
        return (existing, conn)
    }
    let token = generateCSRFToken()
    let updated = conn.putSession(key: config.sessionKey, value: token)
    return (token, updated)
}

// MARK: - Private Helpers

private func generateCSRFToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    #if canImport(Security)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    #else
    for i in 0..<bytes.count {
        bytes[i] = UInt8.random(in: 0...255)
    }
    #endif
    return Base64URL.encode(Data(bytes))
}

private func forbidden(_ conn: Connection) -> Connection {
    var copy = conn
    copy.response.status = .forbidden
    copy.responseBody = .string("Forbidden")
    copy.isHalted = true
    return copy
}

/// Constant-time string comparison to prevent timing attacks.
private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
    let aBytes = Array(a.utf8)
    let bBytes = Array(b.utf8)
    guard aBytes.count == bBytes.count else { return false }
    var result: UInt8 = 0
    for (x, y) in zip(aBytes, bBytes) {
        result |= x ^ y
    }
    return result == 0
}
