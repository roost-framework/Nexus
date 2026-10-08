// MARK: - Remote IP

extension Connection {

    /// The well-known assigns key where the remote IP address is stored.
    ///
    /// Server adapters populate this key during connection construction.
    /// A plug that reads proxy headers (e.g. `X-Forwarded-For`) can
    /// overwrite this key to reflect the true client IP.
    public static let remoteIPKey = "_nexus_remote_ip"

    /// The remote IP address of the client, if available.
    ///
    /// Populated by the server adapter (e.g., `NexusHummingbirdAdapter`).
    /// Returns `nil` when the adapter does not provide this information
    /// or in testing contexts where no real connection exists.
    ///
    /// To set the remote IP in tests, use
    /// `TestConnection.build(remoteIP: "127.0.0.1")`.
    public var remoteIP: String? {
        self[RemoteIPKey.self] ?? assigns[Self.remoteIPKey] as? String
    }
}
