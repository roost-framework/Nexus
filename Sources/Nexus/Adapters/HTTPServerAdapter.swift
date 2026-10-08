/// A type that bridges a Nexus plug pipeline to a concrete HTTP server.
///
/// The adapter pattern decouples the plug layer from the server implementation.
/// Define your application logic once as a ``Plug`` pipeline; swap the adapter
/// to run on a different server.
///
/// ## Implementing an Adapter
///
/// ```swift
/// final class NIOAdapter: HTTPServerAdapter {
///     private var plug: Plug?
///     private let port: Int
///
///     init(port: Int) { self.port = port }
///
///     func configure(plug: @escaping Plug) {
///         self.plug = plug
///     }
///
///     func run() async throws {
///         // Start NIO server on port, call self.plug for each request
///     }
/// }
/// ```
///
/// ## Using an Adapter
///
/// ```swift
/// let app = pipeline([requestId(), logger, router])
/// let adapter = NIOAdapter(port: 8080)
/// adapter.configure(plug: app)
/// try await adapter.run()
/// ```
///
/// > Note: The existing `NexusHummingbirdAdapter` (`NexusHummingbird` target)
/// > implements this pattern using Hummingbird's `HTTPResponder`. Refer to its
/// > source for a complete example.
///
/// > Important: Server lifecycle — start, stop, graceful shutdown — is
/// > intentionally left to the concrete adapter because it depends on the
/// > underlying server framework's API.
public protocol HTTPServerAdapter: Sendable {

    /// Supplies the root plug that the adapter will invoke for every request.
    ///
    /// Called once before ``run()``. The adapter should retain the plug and
    /// use it to process each incoming request by converting the server's
    /// request type to a ``Connection``, calling the plug, and converting
    /// the resulting ``Connection`` back to the server's response type.
    ///
    /// - Parameter plug: The root ``Plug`` (or pipeline) for the application.
    func configure(plug: @escaping Plug)

    /// Starts the HTTP server and runs until shutdown.
    ///
    /// This method should block (or suspend) until the server stops. Throw to
    /// propagate an unrecoverable startup or runtime error.
    ///
    /// - Throws: Any unrecoverable error that prevents the server from running.
    func run() async throws
}
