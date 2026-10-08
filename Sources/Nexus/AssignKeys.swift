/// Typed key for the unique request ID assigned by ``requestId(generator:headerName:)``.
public enum RequestIdKey: AssignKey {
    public typealias Value = String
}

/// Typed key for the session dictionary managed by the session plug.
public enum SessionKey: AssignKey {
    public typealias Value = [String: String]
}

/// Typed key for the remote IP address populated by the server adapter.
public enum RemoteIPKey: AssignKey {
    public typealias Value = String
}

/// Typed key for merged text parameters from body parsing.
///
/// Populated by ``bodyParser(_:)`` for URL-encoded and multipart requests.
public enum BodyParamsKey: AssignKey {
    public typealias Value = [String: String]
}

/// Typed key for uploaded files from multipart body parsing.
///
/// Populated by ``bodyParser(_:)`` for multipart requests.
public enum UploadedFilesKey: AssignKey {
    public typealias Value = [String: MultipartFile]
}

/// Typed key for the parsed JSON body.
///
/// Populated by ``bodyParser(_:)`` for JSON requests.
public enum ParsedJSONKey: AssignKey {
    public typealias Value = JSONValue
}
