import Foundation
import HTTPTypes

/// Configuration for the session plug.
public struct SessionConfig: Sendable {

    /// The secret key for HMAC-SHA256 signing of session cookies.
    ///
    /// Must be at least 32 bytes for adequate security. This key must
    /// remain stable across application restarts — rotating the key
    /// invalidates all existing sessions.
    public var secret: Data

    /// The name of the session cookie. Defaults to `"_nexus_session"`.
    public var cookieName: String

    /// The `Path` attribute on the session cookie. Defaults to `"/"`.
    public var path: String

    /// The `Domain` attribute on the session cookie. Defaults to `nil`.
    public var domain: String?

    /// The `Max-Age` attribute in seconds. Defaults to 86 400 (24 hours).
    public var maxAge: Int?

    /// Whether the cookie requires HTTPS. Defaults to `true`.
    public var secure: Bool

    /// Whether to hide the cookie from JavaScript. Defaults to `true`.
    public var httpOnly: Bool

    /// The `SameSite` attribute. Defaults to `.lax`.
    public var sameSite: Cookie.SameSite

    /// Creates a session configuration.
    ///
    /// - Parameters:
    ///   - secret: The HMAC signing key. Must be at least 32 bytes.
    ///   - cookieName: The cookie name. Defaults to `"_nexus_session"`.
    ///   - path: The cookie path. Defaults to `"/"`.
    ///   - domain: The cookie domain. Defaults to `nil`.
    ///   - maxAge: The cookie max-age in seconds. Defaults to 86 400.
    ///   - secure: Whether to require HTTPS. Defaults to `true`.
    ///   - httpOnly: Whether to hide from JavaScript. Defaults to `true`.
    ///   - sameSite: The SameSite attribute. Defaults to `.lax`.
    public init(
        secret: Data,
        cookieName: String = "_nexus_session",
        path: String = "/",
        domain: String? = nil,
        maxAge: Int? = 86_400,
        secure: Bool = true,
        httpOnly: Bool = true,
        sameSite: Cookie.SameSite = .lax
    ) {
        self.secret = secret
        self.cookieName = cookieName
        self.path = path
        self.domain = domain
        self.maxAge = maxAge
        self.secure = secure
        self.httpOnly = httpOnly
        self.sameSite = sameSite
    }
}

/// A plug that manages signed, cookie-based sessions.
///
/// On each request the plug reads the session cookie, verifies its
/// HMAC-SHA256 signature, deserializes the JSON payload into a
/// `[String: String]` dictionary, and stores it in
/// ``Connection/assigns`` under ``Connection/sessionKey``.
///
/// A `beforeSend` callback serializes the session back into a signed
/// cookie when it has been modified during the request.
///
/// This is the Nexus equivalent of Elixir's `Plug.Session` with a
/// cookie store backed by `Plug.Crypto.MessageVerifier`.
///
/// > Note: Session data is stored **in the cookie** and is therefore
/// > limited to ~4 KB. Keep session values small. The data is signed
/// > but **not encrypted** — do not store secrets in the session.
///
/// ```swift
/// let session = sessionPlug(SessionConfig(
///     secret: Data("my-32-byte-minimum-secret-key!!!".utf8)
/// ))
/// let app = pipeline([session, router])
/// ```
///
/// - Parameter config: The session configuration.
/// - Returns: A plug that manages cookie-based sessions.
public func sessionPlug(_ config: SessionConfig) -> Plug {
    { conn in
        // Fetch once so a nested pipeline cannot discard earlier session changes.
        let hookKey = "nexus.session.\(config.cookieName)"
        guard conn.privateData[hookKey] == nil else { return conn }
        var result = conn.fetchSession(config).putPrivate(hookKey, value: true)

        // --- Write phase (beforeSend) ---
        result = result.registerBeforeSend { c in
            guard c.assigns[Connection.sessionIgnoreKey] as? Bool != true else { return c }
            let touched = c.assigns[Connection.sessionTouchedKey] as? Bool ?? false
            guard touched else { return c }

            let shouldDrop = c.assigns[Connection.sessionDropKey] as? Bool ?? false
            if shouldDrop {
                return c.deleteRespCookie(
                    config.cookieName,
                    path: config.path,
                    domain: config.domain
                )
            }

            let sessionData = c.assigns[Connection.sessionKey] as? [String: String] ?? [:]
            guard let jsonData = try? JSONEncoder().encode(sessionData) else {
                return c
            }

            let token = MessageSigning.sign(payload: jsonData, secret: config.secret)
            let cookie = Cookie(
                name: config.cookieName,
                value: token,
                path: config.path,
                domain: config.domain,
                maxAge: config.maxAge,
                secure: config.secure,
                httpOnly: config.httpOnly,
                sameSite: config.sameSite
            )
            return c.putRespCookie(cookie)
        }

        return result
    }
}
