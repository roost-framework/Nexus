import CNexusZlib
import Foundation
import HTTPTypes

// MARK: - Compression Plug

/// A plug that compresses response bodies based on the `Accept-Encoding` header.
///
/// Registered as a `beforeSend` hook so compression runs after the full
/// response body has been assembled by downstream plugs. Supported algorithms
/// are selected by client quality, then server preference order.
///
/// Currently supports:
/// - `gzip` — standard gzip format (RFC 1952)
/// - `deflate` — zlib-wrapped DEFLATE (RFC 1950)
///
/// ```swift
/// let compression = Compression()
/// let app = pipeline([compression, router])
/// ```
///
/// Only responses with a buffered body of at least `minimumLength` bytes
/// are compressed. Streaming bodies are passed through unchanged.
public struct Compression: Sendable {

    /// Compression algorithms in priority order.
    public enum Algorithm: String, Sendable {
        /// Standard gzip encoding (RFC 1952).
        case gzip = "gzip"
        /// Zlib-wrapped DEFLATE (RFC 1950).
        case deflate = "deflate"
    }

    private let algorithms: [Algorithm]
    private let minimumLength: Int

    /// Creates a `Compression` plug.
    ///
    /// - Parameters:
    ///   - algorithms: Compression algorithms in preference order.
    ///     Defaults to `[.gzip, .deflate]`.
    ///   - minimumLength: Minimum response body size in bytes to trigger
    ///     compression. Defaults to 1024.
    public init(
        algorithms: [Algorithm] = [.gzip, .deflate],
        minimumLength: Int = 1024
    ) {
        self.algorithms = algorithms
        self.minimumLength = minimumLength
    }
}

extension Compression: ModulePlug {

    /// Registers a `beforeSend` hook that compresses the response body.
    ///
    /// - Parameter connection: The incoming connection.
    /// - Returns: The connection with a `beforeSend` compression hook registered.
    public func call(_ connection: Connection) async throws -> Connection {
        let algorithms = self.algorithms
        let minimumLength = self.minimumLength

        return connection.registerBeforeSend { conn in
            guard
                case .buffered(let data) = conn.responseBody,
                !data.isEmpty, data.count >= minimumLength,
                conn.response.headerFields[.contentEncoding] == nil,
                conn.response.headerFields[.contentRange] == nil,
                conn.response.status.code >= 200,
                ![204, 205, 206, 304].contains(conn.response.status.code),
                !(conn.getRespHeader(.cacheControl) ?? "").split(separator: ",").contains(where: {
                    $0.trimmingCharacters(in: .whitespaces).lowercased() == "no-transform"
                })
            else { return conn }

            // Both compressed and identity representations vary with this request header.
            let varied = conn.varying(on: "Accept-Encoding")
            guard conn.request.method != .head,
                let accept = conn.request.headerFields[.acceptEncoding]
            else { return varied }
            let preferences = HTTPPreference.parse(accept)
            let wildcard = preferences.first { $0.value == "*" }?.quality ?? 0
            let identity = preferences.first { $0.value == "identity" }?.quality
            let candidates = algorithms.enumerated().compactMap { index, algorithm -> (Int, Algorithm, Double)? in
                let quality = preferences.first { $0.value == algorithm.rawValue }?.quality ?? wildcard
                guard quality > 0, quality >= (identity ?? 0) else { return nil }
                return (index, algorithm, quality)
            }.sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2 }
            for (_, algorithm, _) in candidates {
                guard let compressed = compress(data, using: algorithm) else { continue }
                var result = varied
                result.responseBody = .buffered(compressed)
                result.response.headerFields[.contentEncoding] = algorithm.rawValue
                result.response.headerFields[.contentLength] = nil
                // A strong validator for the original bytes is not valid for the encoded representation.
                if let etag = result.response.headerFields[.eTag], !etag.hasPrefix("W/") {
                    result.response.headerFields[.eTag] = "W/" + etag
                }
                return result
            }
            return varied
        }
    }
}

/// Uses zlib's format support directly, identically on Apple platforms and Linux.
private func compress(_ data: Data, using algorithm: Compression.Algorithm) -> Data? {
    guard data.count <= Int(UInt32.max) else { return nil }
    var stream = z_stream()
    let windowBits: Int32 = algorithm == .gzip ? 31 : 15
    guard
        deflateInit2_(
            &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, windowBits, 8,
            Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK
    else { return nil }
    defer { deflateEnd(&stream) }
    let bound = deflateBound(&stream, uLong(data.count))
    guard bound <= UInt32.max else { return nil }
    var output = Data(count: Int(bound))
    let status = data.withUnsafeBytes { input in
        output.withUnsafeMutableBytes { buffer in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)
            stream.next_out = buffer.bindMemory(to: UInt8.self).baseAddress
            stream.avail_out = uInt(buffer.count)
            return deflate(&stream, Z_FINISH)
        }
    }
    guard status == Z_STREAM_END else { return nil }
    output.count = Int(stream.total_out)
    return output
}
