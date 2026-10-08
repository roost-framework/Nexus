import Foundation

// MARK: - Body Parser Accessors

extension Connection {

    /// Merged text parameters from URL-encoded forms and multipart fields.
    ///
    /// Populated by the ``bodyParser(_:)`` plug. Returns an empty dictionary
    /// if the plug has not run or the `Content-Type` was not a form type.
    public var bodyParams: [String: String] {
        self[BodyParamsKey.self] ?? [:]
    }

    /// Uploaded files from a multipart request.
    ///
    /// Populated by the ``bodyParser(_:)`` plug. Returns an empty dictionary
    /// if the plug has not run or the request was not multipart.
    public var uploadedFiles: [String: MultipartFile] {
        self[UploadedFilesKey.self] ?? [:]
    }

    /// Returns the uploaded file for the given field name.
    ///
    /// Convenience for `uploadedFiles[name]`.
    ///
    /// - Parameter name: The form field name.
    /// - Returns: The uploaded file, or `nil`.
    public func uploadedFile(_ name: String) -> MultipartFile? {
        uploadedFiles[name]
    }

    /// The parsed JSON body as a ``JSONValue`` for dynamic access.
    ///
    /// Populated by the ``bodyParser(_:)`` plug for JSON requests.
    /// Returns `nil` if the plug has not run or the request was not JSON.
    public var parsedJSON: JSONValue? {
        self[ParsedJSONKey.self]
    }
}
