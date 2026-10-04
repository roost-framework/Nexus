import Foundation
import Vapor
import HTTPTypes
import Nexus

/// Bridges a Nexus plug pipeline to Vapor's middleware layer.
///
/// ``NexusVaporAdapter`` converts an incoming `Request` from Vapor
/// into a Nexus ``Connection``, runs it through a ``Plug`` pipeline, and
/// converts the resulting ``Connection`` back into a Vapor `Response`.
///
/// The adapter implements Vapor's `AsyncMiddleware` protocol, making it
/// directly usable as middleware in a Vapor application.
///
/// ## Overview
///
/// The adapter performs three key transformations:
///
/// 1. **Request Translation**: Converts Vapor's `Request` type to Nexus's
///    ``Connection`` type, including extracting request body data and
///    populating ``Connection/remoteIP`` from the underlying NIO channel.
///
/// 2. **Pipeline Execution**: Runs the Nexus plug pipeline, catching any
///    infrastructure errors per ADR-004 and converting them to HTTP 500
///    responses.
///
/// 3. **Response Translation**: Converts the resulting ``Connection``
///    back to a Vapor `Response`, handling all response body types
///    (empty, buffered, and streaming).
///
/// ## Usage Example
///
/// ```swift
/// import Vapor
/// import NexusVapor
///
/// // Create a Nexus router
/// let router = Router()
/// router.get("hello") { conn in
///     conn.respond(status: .ok, body: .string("Hello from Nexus!"))
/// }
///
/// // Integrate with Vapor
/// let app = Application(.default)
/// app.middleware.use(
///     NexusVaporAdapter(plug: router.handle),
///     at: .root
/// )
///
/// try await app.execute()
/// ```
///
/// ## Error Handling (ADR-004)
///
/// The adapter distinguishes between HTTP-level rejections and infrastructure
/// failures:
///
/// - **Halted connections** (HTTP-level rejections): When a plug returns
///   ``Connection/halted()``, the adapter reads ``Connection/response`` and
///   ``Connection/responseBody`` and returns them as a Vapor `Response`.
///   This is the standard way plugs signal 4xx and 5xx responses.
///
/// - **Thrown errors** (infrastructure failures): When a plug throws an
///   error (e.g., database timeout, I/O failure), the adapter catches it
///   and returns a generic `500 Internal Server Error` response.
///
/// ## Request Body Handling
///
/// The adapter buffers request bodies up to ``maxRequestBodySize`` (default 4 MB).
/// Bodies larger than this limit throw an error during collection. Empty bodies
/// are represented as ``RequestBody/empty``, while non-empty bodies are
/// ``RequestBody/buffered(_:)``.
///
/// ## Response Body Handling
///
/// All ``ResponseBody`` cases are supported:
///
/// - ``ResponseBody/empty`` - Returns a response with no body
/// - ``ResponseBody/buffered(_:)`` - Returns the complete response data
/// - ``ResponseBody/stream(_:)`` - Streams the response asynchronously
/// - ``ResponseBody/producer(_:)`` - Runs a lazy producer with awaited writes
///
/// ## Lifecycle Hooks
///
/// Before converting the ``Connection`` to a Vapor response, the adapter
/// executes ``Connection/runBeforeSend()`` to invoke any registered lifecycle
/// hooks (see ADR-006). This allows plugs to perform post-processing
/// (e.g., response headers, logging) just before the response is sent.
///
/// ## Remote IP Address
///
/// The adapter automatically extracts the client's IP address from the
/// Vapor request's NIO channel and stores it in ``Connection/remoteIP``.
/// This makes the remote address available to all downstream plugs.
///
/// ## Related Types
///
/// - ``Plug`` - The function type that processes connections
/// - ``Connection`` - The core state type that flows through the pipeline
/// - ``RequestBody`` - Enum representing request body states
/// - ``ResponseBody`` - Enum representing response body states
public struct NexusVaporAdapter: Sendable {

    /// The root plug that processes every incoming request.
    ///
    /// This plug receives connections after they've been converted from
    /// Vapor requests and before they're converted back to Vapor responses.
    private let plug: Plug

    /// Maximum number of bytes to buffer from the request body.
    ///
    /// Bodies exceeding this limit will cause the request to fail.
    /// Default is 4 MB (4,194,304 bytes).
    private let maxRequestBodySize: Int

    /// Creates an adapter that wraps the given plug pipeline.
    ///
    /// Use this initializer to create a Vapor middleware that delegates
    /// request handling to a Nexus plug pipeline.
    ///
    /// - Parameters:
    ///   - plug: The root plug that handles every incoming request.
    ///     This plug receives the connection after request translation
    ///     and before response translation.
    ///   - maxRequestBodySize: Maximum number of bytes to buffer from the
    ///     request body. Defaults to 4 MB (4,194,304 bytes). Requests
    ///     exceeding this limit will fail during body collection.
    ///
    /// - Returns: A new ``NexusVaporAdapter`` instance ready for use
    ///   as Vapor middleware.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let adapter = NexusVaporAdapter(
    ///     plug: myRouter.handle,
    ///     maxRequestBodySize: 8_388_608 // 8 MB
    /// )
    /// app.middleware.use(adapter, at: .root)
    /// ```
    public init(plug: @escaping Plug, maxRequestBodySize: Int = 4_194_304) {
        self.plug = plug
        self.maxRequestBodySize = maxRequestBodySize
    }
}

// MARK: - AsyncMiddleware

extension NexusVaporAdapter: AsyncMiddleware {

    /// Converts a Vapor request into a Nexus ``Connection``, runs it
    /// through the plug pipeline, and converts the result back into a
    /// Vapor response.
    ///
    /// This method is called by Vapor for each incoming request. The adapter
    /// performs the full request/response cycle, including error handling
    /// per ADR-004 and lifecycle hook execution per ADR-006.
    ///
    /// ## Translation Process
    ///
    /// 1. **Request Translation**: Converts the Vapor `Request` to a Nexus
    ///    ``Connection``, including:
    ///    - Extracting request body data (up to ``maxRequestBodySize``)
    ///    - Populating ``Connection/remoteIP`` from the NIO channel
    ///    - Converting headers and URI components
    ///
    /// 2. **Pipeline Execution**: Runs the plug pipeline with error handling:
    ///    - Executes the ``plug`` pipeline
    ///    - Catches infrastructure errors and converts to HTTP 500
    ///    - Preserves halted connections (HTTP-level rejections)
    ///
    /// 3. **Lifecycle Hooks**: Executes ``Connection/runBeforeSend()`` to
    ///    invoke any registered lifecycle hooks.
    ///
    /// 4. **Response Translation**: Converts the ``Connection`` back to a
    ///    Vapor `Response`, handling all ``ResponseBody`` cases.
    ///
    /// ## Error Handling
    ///
    /// - **Body collection errors**: Thrown if the request body exceeds
    ///   ``maxRequestBodySize``. These errors propagate to Vapor's error
    ///   handling middleware.
    /// - **Pipeline errors**: Caught and converted to HTTP 500 responses
    ///   per ADR-004. The error is not re-thrown.
    /// - **Halted connections**: Returned as-is with the status and body
    ///   set by the plug that halted the connection.
    ///
    /// ## Related Types
    ///
    /// - ``Connection`` - The state type flowing through the pipeline
    /// - ``RequestBody`` - Request body representation
    /// - ``ResponseBody`` - Response body representation
    /// - ``Connection/runBeforeSend()`` - Lifecycle hook execution
    ///
    /// - Parameters:
    ///   - request: The incoming Vapor request containing headers, body,
    ///     URI, and other request metadata.
    ///   - next: The next middleware in the Vapor chain. This parameter
    ///     is not used because ``NexusVaporAdapter`` is a terminal
    ///     middleware that handles the request completely.
    ///
    /// - Returns: A Vapor `Response` built from the pipeline result.
    ///   The response includes the status code, headers, and body from
    ///   the final ``Connection``.
    ///
    /// - Throws: Only if request body collection exceeds ``maxRequestBodySize``.
    ///   All other errors (including pipeline errors) are caught and
    ///   converted to HTTP 500 responses per ADR-004.
    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // 1. Convert Vapor Request → Nexus Connection
        let bodyBuffer: ByteBuffer
        if let collected = request.body.data {
            guard collected.readableBytes <= maxRequestBodySize else { throw Abort(.payloadTooLarge) }
            bodyBuffer = collected
        } else {
            bodyBuffer = try await request.body.collect(upTo: maxRequestBodySize)
        }
        let data = Data(bodyBuffer.readableBytesView)
        let nexusRequestBody: Nexus.RequestBody = data.isEmpty ? .empty : .buffered(data)

        // Preserve the request target and every header field, including repeated cookies.
        let uri = request.url
        let authority: String
        if let host = uri.host {
            let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
            authority = bracketed + (uri.port.map { ":\($0)" } ?? "")
        } else {
            authority = request.headers.first(name: .host) ?? "localhost"
        }
        var httpRequest = HTTPRequest(
            method: request.method.toHTTPRequestMethod,
            scheme: uri.scheme ?? "http",
            authority: authority,
            path: uri.path + (uri.query.map { "?" + $0 } ?? "")
        )
        for header in request.headers {
            guard let name = HTTPField.Name(header.name) else { continue }
            httpRequest.headerFields.append(HTTPField(name: name, value: header.value))
        }

        var connection = Connection(
            request: httpRequest,
            requestBody: nexusRequestBody
        )

        // 1b. Populate remote IP from Vapor's request context
        if let ip = request.remoteAddress?.ipAddress {
            connection = connection.assign(key: Connection.remoteIPKey, value: ip)
        }

        // 2. Run the plug pipeline, catching infrastructure errors (ADR-004)
        let result: Connection
        do {
            result = try await plug(connection)
        } catch {
            return Response(
                status: .internalServerError,
                headers: [:],
                body: .empty
            )
        }

        // 3. Run lifecycle hooks before serializing the response (ADR-006)
        let finalResult = result.runBeforeSend()

        // 4. Convert Nexus Connection → Vapor Response
        let body: Response.Body
        switch finalResult.responseBody {
        case .empty:
            body = .empty
        case .buffered(let data):
            body = .init(data: data)
        case .stream(let stream):
            body = .init(managedAsyncStream: { writer in
                for try await chunk in stream {
                    try Task.checkCancellation()
                    try await writer.write(.buffer(ByteBuffer(bytes: chunk)))
                }
            })
        case .producer(let produce):
            body = .init(managedAsyncStream: { transport in
                var writer: any Nexus.ResponseBodyWriter = VaporBodyWriter(base: transport)
                try Task.checkCancellation()
                try await produce(&writer)
                try Task.checkCancellation()
            })
        }
        var headers = HTTPHeaders()
        for field in finalResult.response.headerFields {
            headers.add(name: field.name.rawName, value: field.value)
        }
        let response = Response(
            status: HTTPResponseStatus(
                statusCode: finalResult.response.status.code,
                reasonPhrase: finalResult.response.status.reasonPhrase
            ),
            headers: headers,
            body: body
        )
        let status = finalResult.response.status.code
        if request.method == .HEAD || status < 200 || [204, 205, 304].contains(status) {
            // Vapor derives Content-Length from Body; HEAD and 304 describe the selected representation instead.
            let contentLength: String?
            switch status {
            case ..<200, 204: contentLength = nil
            case 205: contentLength = "0"
            case 304: contentLength = finalResult.response.headerFields[.contentLength]
            default:
                contentLength =
                    finalResult.response.headerFields[.contentLength]
                    ?? response.headers.first(name: .contentLength)
            }
            response.body = .empty
            response.headers.remove(name: .contentLength)
            response.headers.remove(name: .transferEncoding)
            if let contentLength { response.headers.add(name: .contentLength, value: contentLength) }
        }
        return response
    }
}

private struct VaporBodyWriter: Nexus.ResponseBodyWriter {
    let base: any AsyncBodyStreamWriter

    func write(_ data: Data) async throws {
        try Task.checkCancellation()
        try await base.write(.buffer(ByteBuffer(bytes: data)))
        try Task.checkCancellation()
    }
}
