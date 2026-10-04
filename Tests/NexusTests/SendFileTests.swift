import Foundation
import HTTPTypes
import Testing

@testable import Nexus

@Suite("Send File")
struct SendFileTests {

    private func makeConnection() -> Connection {
        let request = HTTPRequest(
            method: .get,
            scheme: "https",
            authority: "example.com",
            path: "/"
        )
        return Connection(request: request)
    }

    private func createTempFile(
        content: Data,
        extension ext: String = "txt"
    ) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let name = UUID().uuidString + ".\(ext)"
        let url = dir.appendingPathComponent(name)
        try content.write(to: url)
        return url.path
    }

    @Test("test_sendFile_setsProducerResponseBody")
    func test_sendFile_setsProducerResponseBody() throws {
        let path = try createTempFile(content: Data("hello".utf8))
        let conn = try makeConnection().sendFile(path: path)
        if case .producer = conn.responseBody {
            // expected
        } else {
            Issue.record("Expected .producer responseBody")
        }
    }

    @Test("test_sendFile_haltsConnection")
    func test_sendFile_haltsConnection() throws {
        let path = try createTempFile(content: Data("hello".utf8))
        let conn = try makeConnection().sendFile(path: path)
        #expect(conn.isHalted == true)
    }

    @Test("test_sendFile_setsContentType_html")
    func test_sendFile_setsContentType_html() throws {
        let path = try createTempFile(content: Data("<h1>hi</h1>".utf8), extension: "html")
        let conn = try makeConnection().sendFile(path: path)
        #expect(conn.response.headerFields[.contentType] == "text/html")
    }

    @Test("test_sendFile_setsContentType_json")
    func test_sendFile_setsContentType_json() throws {
        let path = try createTempFile(content: Data("{}".utf8), extension: "json")
        let conn = try makeConnection().sendFile(path: path)
        #expect(conn.response.headerFields[.contentType] == "application/json")
    }

    @Test("test_sendFile_customContentType_overridesInference")
    func test_sendFile_customContentType_overridesInference() throws {
        let path = try createTempFile(content: Data("data".utf8), extension: "html")
        let conn = try makeConnection().sendFile(path: path, contentType: "text/plain")
        #expect(conn.response.headerFields[.contentType] == "text/plain")
    }

    @Test("test_sendFile_notFound_throwsNexusHTTPError")
    func test_sendFile_notFound_throwsNexusHTTPError() {
        let conn = makeConnection()
        #expect(throws: NexusHTTPError.self) {
            try conn.sendFile(path: "/nonexistent/path/file.txt")
        }
    }

    @Test("test_sendFile_notFound_statusIs404")
    func test_sendFile_notFound_statusIs404() {
        let conn = makeConnection()
        do {
            _ = try conn.sendFile(path: "/nonexistent/path/file.txt")
            Issue.record("Expected NexusHTTPError")
        } catch let error as NexusHTTPError {
            #expect(error.status == .notFound)
        } catch {
            Issue.record("Expected NexusHTTPError, got \(error)")
        }
    }

    @Test("test_sendFile_streamsFileContents")
    func test_sendFile_streamsFileContents() async throws {
        let content = "Hello, Nexus!"
        let path = try createTempFile(content: Data(content.utf8))
        let conn = try makeConnection().sendFile(path: path)
        guard case .producer(let stream) = conn.responseBody else {
            Issue.record("Expected .producer responseBody")
            return
        }
        var received = Data()
        for data in try await collectProducer(stream) {
            received.append(data)
        }
        #expect(String(data: received, encoding: .utf8) == content)
    }

    @Test("test_sendFile_largeFile_chunked")
    func test_sendFile_largeFile_chunked() async throws {
        let chunkSize = 1024
        let content = Data(repeating: 0x41, count: chunkSize * 3 + 100)
        let path = try createTempFile(content: content)
        let conn = try makeConnection().sendFile(path: path, chunkSize: chunkSize)
        guard case .producer(let stream) = conn.responseBody else {
            Issue.record("Expected .producer responseBody")
            return
        }
        var chunkCount = 0
        var received = Data()
        for data in try await collectProducer(stream) {
            chunkCount += 1
            received.append(data)
        }
        #expect(chunkCount == 4)
        #expect(received == content)
    }

    @Test("test_sendFile_defaultMimeType_octetStream")
    func test_sendFile_defaultMimeType_octetStream() throws {
        let path = try createTempFile(content: Data("binary".utf8), extension: "xyz")
        let conn = try makeConnection().sendFile(path: path)
        #expect(conn.response.headerFields[.contentType] == "application/octet-stream")
    }
}
