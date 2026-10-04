import Foundation

// MARK: - Session Helpers

extension Connection {

    /// The assigns key used to store session data.
    public static let sessionKey = "_nexus_session"

    /// The assigns key that signals the session cookie should be deleted.
    static let sessionDropKey = "_nexus_session_drop"

    /// The assigns key that tracks whether the session was read or written.
    static let sessionTouchedKey = "_nexus_session_touched"

    /// Whether session writes should be suppressed for this response.
    static let sessionIgnoreKey = "_nexus_session_ignore"

    /// The current session dictionary, or an empty dictionary if no session
    /// has been established.
    var sessionData: [String: String] {
        assigns[Connection.sessionKey] as? [String: String] ?? [:]
    }

    /// Reads a value from the session.
    ///
    /// - Parameter key: The session key to look up.
    /// - Returns: The value associated with the key, or `nil` if not present.
    public func getSession(_ key: String) -> String? {
        sessionData[key]
    }

    /// Returns all session values, or an empty dictionary before fetching.
    /// - Returns: The current session dictionary.
    public func getSession() -> [String: String] { sessionData }

    /// Reads a session value, returning `defaultValue` when the key is absent.
    /// - Parameters:
    ///   - key: The session key.
    ///   - defaultValue: The fallback value.
    /// - Returns: The session value or the supplied fallback.
    public func getSession(_ key: String, default defaultValue: String) -> String {
        sessionData[key] ?? defaultValue
    }

    /// Writes a key–value pair to the session.
    ///
    /// The updated session is serialized back to the session cookie by the
    /// ``sessionPlug(_:)`` plug's `beforeSend` callback.
    ///
    /// - Parameters:
    ///   - key: The session key.
    ///   - value: The value to store.
    /// - Returns: A new connection with the updated session.
    public func putSession(key: String, value: String) -> Connection {
        var session = sessionData
        session[key] = value
        return assign(key: Connection.sessionKey, value: session)
            .assign(key: Connection.sessionTouchedKey, value: true)
    }

    /// Removes a single key from the session.
    ///
    /// - Parameter key: The session key to remove.
    /// - Returns: A new connection with the key removed from the session.
    public func deleteSession(_ key: String) -> Connection {
        var session = sessionData
        session.removeValue(forKey: key)
        return assign(key: Connection.sessionKey, value: session)
            .assign(key: Connection.sessionTouchedKey, value: true)
    }

    /// Removes all session data and marks the session cookie for deletion.
    ///
    /// The ``sessionPlug(_:)`` plug's `beforeSend` callback will emit a
    /// `Set-Cookie` header with `Max-Age=0` to instruct the browser to
    /// remove the cookie.
    ///
    /// Pass `drop: false` for Plug's `clear_session` semantics: clear the data
    /// while retaining an empty session cookie. The default preserves Nexus's
    /// existing logout behavior of deleting the cookie.
    /// - Parameter drop: Whether to delete the cookie, rather than write an empty session.
    /// - Returns: A new connection with the session cleared.
    public func clearSession(drop: Bool = true) -> Connection {
        assign(key: Connection.sessionKey, value: [String: String]())
            .assign(key: Connection.sessionDropKey, value: drop)
            .assign(key: Connection.sessionTouchedKey, value: true)
    }

    /// Marks the session for renewal, triggering the session plug to re-issue
    /// the session cookie with a fresh expiry on the next response.
    ///
    /// This cookie store has no server-side session ID to rotate. Renewal
    /// reissues the signed data; it does not invalidate previously issued tokens.
    /// Has no effect if no session plug is in the pipeline.
    ///
    /// - Returns: A new connection with the session marked as touched.
    public func renewSession() -> Connection {
        assign(key: Connection.sessionTouchedKey, value: true)
            .assign(key: Connection.sessionDropKey, value: false)
            .assign(key: Connection.sessionIgnoreKey, value: false)
    }

    /// Configures session persistence for this response.
    /// `ignore` suppresses writes; `drop` deletes the cookie; `renew` reissues it.
    /// When several options are true, renew takes precedence over drop, then ignore, as in Plug.
    /// Changes remain readable within the request even when persistence is ignored.
    /// - Parameters:
    ///   - renew: Reissue the signed session cookie.
    ///   - drop: Delete the session cookie.
    ///   - ignore: Suppress session cookie writes for this response.
    /// - Returns: A new connection with persistence configured.
    public func configureSession(renew: Bool = false, drop: Bool = false, ignore: Bool = false) -> Connection {
        if renew { return renewSession() }
        if drop {
            return assign(key: Self.sessionDropKey, value: true)
                .assign(key: Self.sessionIgnoreKey, value: false)
                .assign(key: Self.sessionTouchedKey, value: true)
        }
        return ignore ? assign(key: Self.sessionIgnoreKey, value: true) : self
    }

    // MARK: - Session Fetch Helpers

    /// Whether the session has been loaded into this connection's assigns.
    ///
    /// Returns `true` after ``sessionPlug(_:)`` has run, or after
    /// ``fetchSession(_:)`` has been called explicitly.
    public var isSessionFetched: Bool {
        assigns[Connection.sessionKey] != nil
    }

    /// Fetches the session from the request cookies using the given configuration.
    ///
    /// Replicates the read phase of ``sessionPlug(_:)`` for cases where
    /// session loading must happen conditionally (e.g., only on authenticated
    /// routes). If the cookie is absent or has an invalid signature,
    /// an empty session is stored — this method never halts the pipeline.
    ///
    /// To write the session back to a cookie, the connection must still pass
    /// through a ``sessionPlug(_:)`` or equivalent `beforeSend` hook.
    ///
    /// ```swift
    /// // Only fetch session on protected routes
    /// if path.hasPrefix("/dashboard") {
    ///     conn = conn.fetchSession(sessionConfig)
    /// }
    /// let userId = conn.getSession("user_id")
    /// ```
    ///
    /// - Parameter config: The session configuration.
    /// - Returns: A new connection with session data stored in assigns.
    public func fetchSession(_ config: SessionConfig) -> Connection {
        guard !isSessionFetched else { return self }
        let session: [String: String]
        if let cookieValue = reqCookies[config.cookieName],
           let payloadData = MessageSigning.verify(token: cookieValue, secret: config.secret),
           let decoded = try? JSONDecoder().decode([String: String].self, from: payloadData) {
            session = decoded
        } else {
            session = [:]
        }
        return assign(key: Connection.sessionKey, value: session)
    }

    /// Fetches the session only if it has not already been loaded.
    ///
    /// Returns the receiver unchanged when ``isSessionFetched`` is already
    /// `true`. Use this to avoid redundant cookie parsing when multiple plugs
    /// may attempt to load the session.
    ///
    /// - Parameter config: The session configuration.
    /// - Returns: A connection with session data available.
    public func fetchSessionIfMissing(_ config: SessionConfig) -> Connection {
        guard !isSessionFetched else { return self }
        return fetchSession(config)
    }
}
