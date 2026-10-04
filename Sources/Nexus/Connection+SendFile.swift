import Foundation
import HTTPTypes

// MARK: - File Serving

extension Connection {

    /// Returns a halted connection that streams the contents of a file as
    /// the response body.
    ///
    /// The file is opened when the adapter sends the body. Each chunk is read
    /// only after the previous write completes, and the file is closed on
    /// completion, cancellation, or write failure. `Content-Type` is inferred
    /// from the file extension when not provided explicitly.
    ///
    /// > Important: This method does **not** validate the path against
    /// > directory traversal attacks. Callers that serve user-provided paths
    /// > must sanitize the input before calling `sendFile`.
    ///
    /// ```swift
    /// // Serve a static asset
    /// return try conn.sendFile(path: "/var/www/index.html")
    /// ```
    ///
    /// - Parameters:
    ///   - path: The absolute file system path to the file.
    ///   - contentType: The MIME type. When `nil`, inferred from the file
    ///     extension via a built-in mapping. Defaults to `nil`.
    ///   - chunkSize: The number of bytes per stream chunk. Defaults to
    ///     65 536 (64 KB). Must be positive.
    /// - Returns: A halted connection with a streaming response body and
    ///   the `Content-Type` header set.
    /// - Throws: ``NexusHTTPError`` with `.notFound` if the file does not
    ///   exist, or `.internalServerError` for an invalid chunk size or an
    ///   unreadable file. Errors opening or reading the file during delivery
    ///   terminate the response stream.
    public func sendFile(
        path: String,
        contentType: String? = nil,
        chunkSize: Int = 65_536
    ) throws -> Connection {
        guard chunkSize > 0 else {
            throw NexusHTTPError(.internalServerError, message: "File chunk size must be positive")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw NexusHTTPError(.notFound, message: "File not found")
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw NexusHTTPError(.internalServerError, message: "Cannot open file")
        }

        let resolvedContentType: String
        if let contentType {
            resolvedContentType = contentType
        } else {
            let ext = (path as NSString).pathExtension
            resolvedContentType = mimeType(forExtension: ext)
        }

        return putRespContentType(resolvedContentType).sendChunked { writer in
            try Task.checkCancellation()
            let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
            defer { try? fileHandle.close() }
            while true {
                try Task.checkCancellation()
                guard let data = try fileHandle.read(upToCount: chunkSize),
                    !data.isEmpty
                else { return }
                try await writer.write(data)
            }
        }
    }
}
