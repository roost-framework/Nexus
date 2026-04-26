import Foundation
import HTTPTypes

/// Configuration for the static file serving plug.
public struct StaticFilesConfig: Sendable {

    /// The URL path prefix to match (e.g. `"/static"`).
    public var at: String

    /// The filesystem directory to serve files from.
    ///
    /// Resolved to an absolute path at initialization time to avoid
    /// sensitivity to working directory changes after app startup.
    public var from: String

    /// When set, only files with these extensions are served.
    /// Other extensions pass through to downstream plugs.
    public var only: Set<String>?

    /// When set, files with these extensions are never served.
    /// They pass through to downstream plugs.
    public var except: Set<String>?

    /// The number of bytes per stream chunk, forwarded to
    /// ``Connection/sendFile(path:contentType:chunkSize:)``.
    public var chunkSize: Int

    /// Creates a static files configuration.
    ///
    /// - Parameters:
    ///   - at: The URL path prefix to match (e.g. `"/static"`).
    ///   - from: The filesystem directory to serve from. Resolved to an
    ///     absolute path immediately.
    ///   - only: An optional allowlist of file extensions. Defaults to `nil`.
    ///   - except: An optional denylist of file extensions. Defaults to `nil`.
    ///   - chunkSize: Bytes per stream chunk. Defaults to 65 536.
    public init(
        at: String,
        from: String,
        only: Set<String>? = nil,
        except: Set<String>? = nil,
        chunkSize: Int = 65_536
    ) {
        // Normalize: strip trailing slash from prefix
        self.at = at.hasSuffix("/") ? String(at.dropLast()) : at
        // Resolve to absolute path at config time
        let url = URL(fileURLWithPath: from).standardized
        self.from = url.path
        self.only = only
        self.except = except
        self.chunkSize = chunkSize
    }
}

/// A plug that serves static files from a directory.
///
/// Maps a URL prefix to a filesystem directory and streams matching
/// files. This is the Nexus equivalent of Elixir's `Plug.Static`.
///
/// Only responds to GET and HEAD requests. Other methods pass through.
/// When a file is not found, sets 404 status **without halting**, so
/// downstream plugs (e.g. a router) can handle the path.
///
/// ```swift
/// let app = pipeline([
///     staticFiles(StaticFilesConfig(at: "/static", from: "./priv/static")),
///     router
/// ])
/// ```
///
/// - Parameter config: The static files configuration.
/// - Returns: A plug that serves static files.
public func staticFiles(_ config: StaticFilesConfig) -> Plug {
    { conn in
        // Only serve GET and HEAD
        guard conn.request.method == .get || conn.request.method == .head else {
            return conn
        }

        let fullPath = conn.request.path ?? "/"
        let requestPath = String(fullPath.split(separator: "?", maxSplits: 1).first ?? Substring(fullPath))

        // Must match the URL prefix
        let prefix = config.at
        guard requestPath == prefix || requestPath.hasPrefix(prefix + "/") else {
            return conn
        }

        // Strip prefix to get the relative path
        let relativePath: String
        if requestPath == prefix {
            // Requesting the prefix itself with no file — pass through
            return conn
        } else {
            relativePath = String(requestPath.dropFirst(prefix.count + 1))
        }

        // Reject empty relative paths
        guard !relativePath.isEmpty else {
            return conn
        }

        // Path traversal protection
        let segments = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        for segment in segments {
            if segment == ".." {
                var copy = conn
                copy.response.status = .forbidden
                copy.responseBody = .string("Forbidden")
                copy.isHalted = true
                return copy
            }
        }

        // Null byte protection
        if relativePath.contains("\0") {
            var copy = conn
            copy.response.status = .forbidden
            copy.responseBody = .string("Forbidden")
            copy.isHalted = true
            return copy
        }

        // Extension filtering
        let ext = (relativePath as NSString).pathExtension.lowercased()
        if let only = config.only, !only.contains(ext) {
            var copy = conn
            copy.response.status = .notFound
            copy.responseBody = .string("Not Found")
            return copy
        }
        if let except = config.except, except.contains(ext) {
            var copy = conn
            copy.response.status = .notFound
            copy.responseBody = .string("Not Found")
            return copy
        }

        // Resolve the full filesystem path
        let fileURL = URL(fileURLWithPath: config.from)
            .appendingPathComponent(relativePath)
            .standardized
        let filePath = fileURL.path

        // Defense in depth: verify resolved path is still under the root
        let resolvedRoot = URL(fileURLWithPath: config.from).standardized.path
        guard filePath.hasPrefix(resolvedRoot) else {
            var copy = conn
            copy.response.status = .forbidden
            copy.responseBody = .string("Forbidden")
            copy.isHalted = true
            return copy
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: filePath) else {
            // 404 without halting — let downstream plugs handle it
            var copy = conn
            copy.response.status = .notFound
            copy.responseBody = .string("Not Found")
            return copy
        }

        // Serve the file
        let result = try conn.sendFile(path: filePath, chunkSize: config.chunkSize)

        // HEAD: keep headers but clear the body
        if conn.request.method == .head {
            var headResult = result
            headResult.responseBody = .empty
            return headResult
        }

        return result
    }
}
