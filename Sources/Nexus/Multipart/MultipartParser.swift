import Foundation

/// Internal parser for RFC 2046 multipart/form-data bodies.
enum MultipartParser {

    /// Parses a multipart/form-data body into fields and files.
    ///
    /// - Parameters:
    ///   - data: The raw request body data.
    ///   - boundary: The boundary string from the Content-Type header.
    /// - Returns: Parsed multipart parameters.
    /// - Throws: ``NexusHTTPError`` with `.badRequest` for malformed bodies.
    static func parse(data: Data, boundary: String) throws -> MultipartParams {
        let delimiter = Data("--\(boundary)".utf8)
        let closeDelimiter = Data("--\(boundary)--".utf8)
        let crlf = Data([0x0D, 0x0A])
        let doubleCRLF = Data([0x0D, 0x0A, 0x0D, 0x0A])
        let lf = Data([0x0A])
        let doubleLF = Data([0x0A, 0x0A])

        var fields: [String: String] = [:]
        var files: [String: MultipartFile] = [:]

        // Split body into parts at boundary markers
        let parts = splitParts(data: data, delimiter: delimiter, closeDelimiter: closeDelimiter)

        for partData in parts {
            // Find header/body separator (double CRLF or double LF)
            let headerEnd: Data.Index
            let separatorLength: Int

            if let crlfIndex = partData.range(of: doubleCRLF)?.lowerBound {
                headerEnd = crlfIndex
                separatorLength = doubleCRLF.count
            } else if let lfIndex = partData.range(of: doubleLF)?.lowerBound {
                headerEnd = lfIndex
                separatorLength = doubleLF.count
            } else {
                // No header/body separator — skip this part
                continue
            }

            let headerData = partData[partData.startIndex..<headerEnd]
            let bodyStart = partData.index(headerEnd, offsetBy: separatorLength)
            var bodyData = partData[bodyStart...]

            // Strip trailing CRLF or LF from body
            if bodyData.hasSuffix(crlf) {
                bodyData = bodyData.dropLast(2)
            } else if bodyData.hasSuffix(lf) {
                bodyData = bodyData.dropLast(1)
            }

            guard let headerString = String(data: headerData, encoding: .utf8) else {
                continue
            }

            let headers = parsePartHeaders(headerString)

            guard let disposition = headers["content-disposition"] else {
                continue
            }

            guard let name = extractParam(from: disposition, param: "name") else {
                continue
            }

            let filename = extractParam(from: disposition, param: "filename")
            let contentType = headers["content-type"]

            if let filename {
                // File part
                files[name] = MultipartFile(
                    filename: filename,
                    contentType: contentType?.trimmingCharacters(in: .whitespaces),
                    data: Data(bodyData)
                )
            } else {
                // Text field
                if let value = String(data: bodyData, encoding: .utf8) {
                    fields[name] = value
                }
            }
        }

        return MultipartParams(fields: fields, files: files)
    }

    /// Extracts the boundary string from a Content-Type header value.
    ///
    /// - Parameter contentType: The full Content-Type header value.
    /// - Returns: The boundary string, or `nil` if not found.
    static func extractBoundary(from contentType: String) -> String? {
        let parts = contentType.split(separator: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("boundary=") {
                var value = String(trimmed.dropFirst("boundary=".count))
                // Strip optional quotes
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                return value
            }
        }
        return nil
    }

    // MARK: - Private

    /// Splits the body data at boundary markers, returning the content of each part.
    private static func splitParts(
        data: Data,
        delimiter: Data,
        closeDelimiter: Data
    ) -> [Data] {
        var parts: [Data] = []
        var searchStart = data.startIndex

        // Find the first delimiter
        guard let firstRange = data.range(of: delimiter, in: searchStart..<data.endIndex) else {
            return []
        }

        // Skip past the first delimiter and its trailing CRLF/LF
        searchStart = firstRange.upperBound
        searchStart = skipLineEnding(in: data, from: searchStart)

        while searchStart < data.endIndex {
            // Find the next delimiter
            if let nextRange = data.range(of: delimiter, in: searchStart..<data.endIndex) {
                let partData = data[searchStart..<nextRange.lowerBound]
                if !partData.isEmpty {
                    parts.append(Data(partData))
                }

                // Check if this is the close delimiter
                let remaining = data[nextRange.lowerBound...]
                if remaining.starts(with: closeDelimiter) {
                    break
                }

                searchStart = nextRange.upperBound
                searchStart = skipLineEnding(in: data, from: searchStart)
            } else {
                break
            }
        }

        return parts
    }

    /// Advances past a CRLF or LF at the given position.
    private static func skipLineEnding(in data: Data, from index: Data.Index) -> Data.Index {
        guard index < data.endIndex else { return index }
        if data[index] == 0x0D, data.index(after: index) < data.endIndex, data[data.index(after: index)] == 0x0A {
            return data.index(index, offsetBy: 2)
        } else if data[index] == 0x0A {
            return data.index(after: index)
        }
        return index
    }

    /// Parses part headers into a lowercase-keyed dictionary.
    private static func parsePartHeaders(_ headerString: String) -> [String: String] {
        var headers: [String: String] = [:]
        let headerLines = headerString
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
        for line in headerLines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                let value = String(line[line.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        return headers
    }

    /// Extracts a named parameter from a header value.
    ///
    /// Handles both quoted (`name="value"`) and unquoted (`name=value`) forms.
    private static func extractParam(from header: String, param: String) -> String? {
        let search = "\(param)="
        guard let range = header.range(of: search, options: .caseInsensitive) else {
            return nil
        }
        var rest = String(header[range.upperBound...])
        // Handle quoted value
        if rest.hasPrefix("\"") {
            rest = String(rest.dropFirst())
            if let endQuote = rest.firstIndex(of: "\"") {
                return String(rest[rest.startIndex..<endQuote])
            }
            return rest
        }
        // Handle unquoted value (terminated by ; or end of string)
        if let semicolonIndex = rest.firstIndex(of: ";") {
            return String(rest[rest.startIndex..<semicolonIndex])
                .trimmingCharacters(in: .whitespaces)
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Data Suffix Check

extension Data {
    fileprivate func hasSuffix(_ suffix: Data) -> Bool {
        guard count >= suffix.count else { return false }
        return self[index(endIndex, offsetBy: -suffix.count)...] == suffix
    }
}
