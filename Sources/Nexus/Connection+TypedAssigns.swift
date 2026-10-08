// MARK: - Typed Assigns

extension Connection {

    /// Reads a typed value from ``assigns`` using a type-safe key.
    ///
    /// The underlying storage key is the string representation of the key
    /// type, ensuring interoperability with the string-based ``assigns``
    /// dictionary.
    ///
    /// ```swift
    /// let id = conn[RequestIdKey.self]  // String?
    /// ```
    ///
    /// - Parameter key: The metatype of the ``AssignKey`` conformance.
    /// - Returns: The stored value, the key's ``AssignKey/defaultValue``, or
    ///   `nil` if neither exists.
    public subscript<K: AssignKey>(key: K.Type) -> K.Value? {
        get { assigns[String(describing: key)] as? K.Value ?? K.defaultValue }
    }

    // MARK: Built-in Convenience Accessors

    /// The unique request ID assigned by the ``requestId(generator:headerName:)``
    /// plug, or `nil` if the plug has not run.
    public var requestId: String? {
        self[RequestIdKey.self] ?? assigns["request_id"] as? String
    }

    /// The current session dictionary, or `nil` if no session plug has run.
    ///
    /// For mutating the session, prefer ``getSession(_:)``,
    /// ``putSession(key:value:)``, and ``clearSession(drop:)``.
    public var session: [String: String]? {
        self[SessionKey.self] ?? assigns[Connection.sessionKey] as? [String: String]
    }

    /// Returns a copy of this connection with the given typed value merged
    /// into ``assigns``.
    ///
    /// ```swift
    /// conn = conn.assign(RequestIdKey.self, value: "abc-123")
    /// ```
    ///
    /// - Parameters:
    ///   - key: The metatype of the ``AssignKey`` conformance.
    ///   - value: The value to store.
    /// - Returns: A new connection with the value assigned.
    public func assign<K: AssignKey>(_ key: K.Type, value: K.Value) -> Connection {
        assign(key: String(describing: key), value: value)
    }
}
