import Foundation
import HTTPTypes

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

// MARK: - Favicon Plug

/// A plug that serves a static favicon from in-memory data.
///
/// Intercepts requests for the favicon path and responds with the icon.
/// All other requests pass through unchanged.
///
/// ```swift
/// let iconData = try Data(contentsOf: URL(fileURLWithPath: "Public/favicon.ico"))
/// let favicon = Favicon(iconData: iconData)
/// let app = pipeline([favicon, router])
/// ```
public struct Favicon: Sendable {

    private let iconData: Data
    private let iconPath: String
    private let etag: String
    private let cacheControl: String

    /// Creates a `Favicon` plug with in-memory icon data.
    ///
    /// - Parameters:
    ///   - iconData: The raw bytes of the favicon file (`.ico`, `.png`, or
    ///     `.svg`).
    ///   - iconPath: The request path to intercept. Defaults to
    ///     `"/favicon.ico"`.
    ///   - cacheControl: Cache policy for successful and conditional responses.
    public init(
        iconData: Data, iconPath: String = "/favicon.ico", cacheControl: String = "public, max-age=86400"
    ) {
        self.iconData = iconData
        self.iconPath = iconPath
        self.etag = "\"" + SHA256.hash(data: iconData).map { String(format: "%02x", $0) }.joined() + "\""
        self.cacheControl = cacheControl
    }
}

extension Favicon: ModulePlug {

    /// Serves the favicon or passes the request through.
    ///
    /// - Parameter connection: The incoming connection.
    /// - Returns: A halted `200 OK` for a matching GET/HEAD, or an empty `304 Not Modified`
    ///   when a validator matches. Other requests pass through unchanged.
    public func call(_ connection: Connection) async throws -> Connection {
        guard !connection.isHalted,
            connection.request.method == .get || connection.request.method == .head,
            connection.requestPath == iconPath
        else {
            return connection
        }

        let contentType = mimeType(for: iconPath)
        var conn = connection
        conn.response.status = .ok
        conn.response.headerFields[.contentType] = contentType
        conn.response.headerFields[.cacheControl] = cacheControl
        conn.response.headerFields[.eTag] = etag
        conn.response.headerFields[.contentLength] = String(iconData.count)
        let validators = (conn.getReqHeader(.ifNoneMatch) ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if validators.contains(where: { $0 == "*" || $0 == etag || $0 == "W/" + etag }) {
            conn.response.status = .notModified
            conn.responseBody = .empty
            conn.response.headerFields[.contentLength] = nil
        } else {
            conn.responseBody = connection.request.method == .head ? .empty : .buffered(iconData)
        }
        conn.isHalted = true
        return conn
    }
}

// MARK: - Helpers

/// Returns the MIME type for a favicon path based on its file extension.
private func mimeType(for path: String) -> String {
    let lower = path.lowercased()
    if lower.hasSuffix(".png") { return "image/png" }
    if lower.hasSuffix(".svg") { return "image/svg+xml" }
    if lower.hasSuffix(".gif") { return "image/gif" }
    if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
    return "image/x-icon"
}
