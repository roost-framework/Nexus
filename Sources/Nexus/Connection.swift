import Foundation
import HTTPTypes

/// The core unit of state that flows through a Nexus pipeline.
///
/// A `Connection` is a value type that pairs an incoming HTTP request with the
/// response being built up by plugs. Each plug receives a `Connection`, performs
/// its work, and returns a new (possibly modified) `Connection`.
///
/// Plugs signal HTTP-level rejections by halting the connection — setting
/// ``isHalted`` to `true` — rather than throwing. Infrastructure failures
/// (database errors, I/O failures, etc.) are communicated by throwing.
///
/// Arbitrary state can be threaded between plugs via ``assigns``.
public struct Connection: Sendable {

    // MARK: - Request

    /// The incoming HTTP request.
    public var request: HTTPRequest

    /// The body of the incoming HTTP request.
    public var requestBody: RequestBody

    // MARK: - Response

    /// The HTTP response being assembled by the plug pipeline.
    public var response: HTTPResponse

    /// The body of the HTTP response.
    public var responseBody: ResponseBody

    // MARK: - Pipeline Control

    /// When `true`, no further plugs in the pipeline will be invoked.
    ///
    /// Plugs that want to short-circuit processing (e.g. to return a 401)
    /// should set ``responseBody``, update ``response``, and set this to `true`.
    public var isHalted: Bool

    // MARK: - Assigns

    /// A key–value store for passing arbitrary `Sendable` data between plugs.
    ///
    /// Keys are `String`s; values are any `Sendable` type.
    public var assigns: [String: any Sendable]

    /// Framework metadata, isolated from application ``assigns``.
    /// Existing Nexus assigns keys remain supported for source compatibility.
    public var privateData: [String: any Sendable]

    // MARK: - Lifecycle Hooks

    /// Callbacks invoked in LIFO order just before the response is delivered.
    ///
    /// Each callback receives the connection and returns a (possibly modified)
    /// connection. Registered via ``registerBeforeSend(_:)``, executed via
    /// ``runBeforeSend()``. The server adapter is responsible for calling
    /// `runBeforeSend()` before serializing the response.
    public var beforeSend: [@Sendable (Connection) -> Connection]

    // MARK: - Init

    /// Creates a new `Connection` from the given HTTP request.
    ///
    /// - Parameters:
    ///   - request: The incoming HTTP request.
    ///   - requestBody: The body of the request. Defaults to `.empty`.
    public init(request: HTTPRequest, requestBody: RequestBody = .empty) {
        self.request = request
        self.requestBody = requestBody
        self.response = HTTPResponse(status: .ok)
        self.responseBody = .empty
        self.isHalted = false
        self.assigns = [:]
        self.privateData = [:]
        self.beforeSend = []
    }
}

// MARK: - Convenience Mutations

extension Connection {

    /// Returns a copy of this connection with ``isHalted`` set to `true`.
    ///
    /// Use this to terminate the plug pipeline without throwing.
    public func halted() -> Connection {
        var copy = self
        copy.isHalted = true
        return copy
    }

    /// Returns a copy of this connection with the given key–value pair merged
    /// into ``assigns``.
    ///
    /// - Parameters:
    ///   - key: The string key to assign.
    ///   - value: The `Sendable` value to store.
    public func assign(key: String, value: any Sendable) -> Connection {
        var copy = self
        copy.assigns[key] = value
        return copy
    }
}
