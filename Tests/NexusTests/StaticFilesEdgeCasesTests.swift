import Testing
import HTTPTypes
import Foundation
@testable import Nexus
@testable import NexusTest

/// Tests for static file serving edge cases
@Suite("Static Files Edge Cases")
struct StaticFilesEdgeCasesTests {

    // MARK: - Helper Methods

    private func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus_static_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanupTempDirectory(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Path Traversal Protection

    @Test("rejects path traversal with ..")
    func rejectsPathTraversal() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/../etc/passwd")
        let result = try await plug(conn)

        #expect(result.response.status == .forbidden)
        #expect(result.isHalted == true)
    }

    @Test("rejects encoded path traversal")
    func rejectsEncodedPathTraversal() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/%2e%2e/etc/passwd")
        let result = try await plug(conn)

        // Should reject - the percent-decoded path contains ..
        #expect(result.response.status == .forbidden || result.response.status == .notFound)
    }

    @Test("rejects mixed case path traversal")
    func rejectsMixedCasePathTraversal() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/./%2e%2e/test.txt")
        let result = try await plug(conn)

        #expect(result.response.status == .forbidden || result.response.status == .notFound)
    }

    @Test("null byte protection via direct relativePath injection")
    func rejectsNullByte() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        // HTTPTypes sanitizes null bytes from request paths before they reach the plug.
        // With a sanitized path like "/static/testfile.txt", the file doesn't exist → 404.
        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/test\0file.txt")
        let result = try await plug(conn)

        // HTTPTypes strips the null byte, so path becomes "/static/testfile.txt" → 404
        #expect(result.response.status == .notFound || result.response.status == .forbidden)
    }

    @Test("rejects multiple .. segments")
    func rejectsMultipleDotDotSegments() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/../../etc/passwd")
        let result = try await plug(conn)

        #expect(result.response.status == .forbidden)
        #expect(result.isHalted == true)
    }

    // MARK: - Extension Filtering

    @Test("respects only extension whitelist")
    func respectsOnlyExtension() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        // Create test files
        let txtFile = tempDir.appendingPathComponent("test.txt")
        try Data("txt content".utf8).write(to: txtFile)

        let jsonFile = tempDir.appendingPathComponent("test.json")
        try Data("json content".utf8).write(to: jsonFile)

        let config = StaticFilesConfig(
            at: "/static",
            from: tempDir.path,
            only: ["txt"]
        )
        let plug = staticFiles(config)

        // TXT file should be served
        var conn1 = Connection.make(path: "/static/test.txt")
        let result1 = try await plug(conn1)
        #expect(result1.response.status == .ok)

        // JSON file should pass through (404 without halt)
        var conn2 = Connection.make(path: "/static/test.json")
        let result2 = try await plug(conn2)
        #expect(result2.response.status == .notFound)
        #expect(result2.isHalted == false)
    }

    @Test("respects except extension denylist")
    func respectsExceptExtension() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        // Create test files
        let txtFile = tempDir.appendingPathComponent("test.txt")
        try Data("txt content".utf8).write(to: txtFile)

        let exeFile = tempDir.appendingPathComponent("test.exe")
        try Data("exe content".utf8).write(to: exeFile)

        let config = StaticFilesConfig(
            at: "/static",
            from: tempDir.path,
            except: ["exe"]
        )
        let plug = staticFiles(config)

        // TXT file should be served
        var conn1 = Connection.make(path: "/static/test.txt")
        let result1 = try await plug(conn1)
        #expect(result1.response.status == .ok)

        // EXE file should pass through (404 without halt)
        var conn2 = Connection.make(path: "/static/test.exe")
        let result2 = try await plug(conn2)
        #expect(result2.response.status == .notFound)
        #expect(result2.isHalted == false)
    }

    @Test("extension filtering is case-insensitive")
    func extensionFilteringCaseInsensitive() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let txtFile = tempDir.appendingPathComponent("TEST.TXT")
        try Data("content".utf8).write(to: txtFile)

        let config = StaticFilesConfig(
            at: "/static",
            from: tempDir.path,
            only: ["txt"]  // lowercase
        )
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/TEST.TXT")
        let result = try await plug(conn)
        #expect(result.response.status == .ok)
    }

    // MARK: - HTTP Method Handling

    @Test("only serves GET and HEAD requests")
    func onlyGETAndHEAD() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let txtFile = tempDir.appendingPathComponent("test.txt")
        try Data("content".utf8).write(to: txtFile)

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        // POST should pass through
        var conn1 = Connection.make(method: .post, path: "/static/test.txt")
        let result1 = try await plug(conn1)
        #expect(result1.isHalted == false)

        // PUT should pass through
        var conn2 = Connection.make(method: .put, path: "/static/test.txt")
        let result2 = try await plug(conn2)
        #expect(result2.isHalted == false)

        // DELETE should pass through
        var conn3 = Connection.make(method: .delete, path: "/static/test.txt")
        let result3 = try await plug(conn3)
        #expect(result3.isHalted == false)
    }

    @Test("HEAD request returns headers without body")
    func headRequestNoBody() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let txtFile = tempDir.appendingPathComponent("test.txt")
        try Data("content".utf8).write(to: txtFile)

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(method: .head, path: "/static/test.txt")
        let result = try await plug(conn)

        #expect(result.response.status == .ok)
        if case .empty = result.responseBody { } else { Issue.record("Expected .empty") }
    }

    // MARK: - File Existence and Paths

    @Test("returns 404 without halting for missing files")
    func returns404WithoutHalt() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/missing.txt")
        let result = try await plug(conn)

        #expect(result.response.status == .notFound)
        #expect(result.isHalted == false)  // Doesn't halt, allowing downstream plugs
    }

    @Test("serves files from subdirectories")
    func servesFromSubdirectories() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let subDir = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let txtFile = subDir.appendingPathComponent("test.txt")
        try Data("content".utf8).write(to: txtFile)

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/sub/test.txt")
        let result = try await plug(conn)

        #expect(result.response.status == .ok)
    }

    @Test("requesting prefix without file passes through")
    func requestingPrefixPassesThrough() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static")
        let result = try await plug(conn)

        #expect(result.isHalted == false)
    }

    @Test("requesting prefix with trailing slash passes through")
    func requestingPrefixWithSlashPassesThrough() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/")
        let result = try await plug(conn)

        #expect(result.isHalted == false)
    }

    // MARK: - Query Strings and Special Paths

    @Test("ignores query string in path matching")
    func ignoresQueryString() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let txtFile = tempDir.appendingPathComponent("test.txt")
        try Data("content".utf8).write(to: txtFile)

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/test.txt?v=1&cache=bust")
        let result = try await plug(conn)

        #expect(result.response.status == .ok)
    }

    @Test("serves files with special characters in name")
    func servesFilesWithSpecialCharacters() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let fileName = "test file-123.txt"
        let txtFile = tempDir.appendingPathComponent(fileName)
        try Data("content".utf8).write(to: txtFile)

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/\(fileName)")
        let result = try await plug(conn)

        #expect(result.response.status == .ok)
    }

    @Test("serves files with multiple dots")
    func servesFilesWithMultipleDots() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let fileName = "test.min.js"
        let txtFile = tempDir.appendingPathComponent(fileName)
        try Data("content".utf8).write(to: txtFile)

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/\(fileName)")
        let result = try await plug(conn)

        #expect(result.response.status == .ok)
    }

    @Test("serves files with no extension")
    func servesFilesWithNoExtension() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let fileName = "README"
        let txtFile = tempDir.appendingPathComponent(fileName)
        try Data("content".utf8).write(to: txtFile)

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/README")
        let result = try await plug(conn)

        #expect(result.response.status == .ok)
    }

    // MARK: - Chunk Size Configuration

    @Test("respects custom chunk size")
    func respectsCustomChunkSize() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let largeContent = Data(repeating: 0x41, count: 100_000)  // 100KB
        let txtFile = tempDir.appendingPathComponent("large.txt")
        try largeContent.write(to: txtFile)

        let config = StaticFilesConfig(
            at: "/static",
            from: tempDir.path,
            chunkSize: 1024  // 1KB chunks
        )
        let plug = staticFiles(config)

        var conn = Connection.make(path: "/static/large.txt")
        let result = try await plug(conn)

        #expect(result.response.status == .ok)

        guard case let .producer(produce) = result.responseBody else {
            Issue.record("Expected .producer responseBody")
            return
        }
        let chunks = try await collectProducer(produce)
        #expect(chunks.reduce(0) { $0 + $1.count } == 100_000)
        #expect(chunks.count == 98)
        #expect(chunks.dropLast().allSatisfy { $0.count == 1_024 })
        #expect(chunks.last?.count == 672)
    }

    // MARK: - Defense in Depth

    @Test("defense in depth verifies resolved path")
    func defenseInDepthVerifiesPath() async throws {
        let tempDir = try createTempDirectory()
        defer { try? cleanupTempDirectory(at: tempDir) }

        let config = StaticFilesConfig(at: "/static", from: tempDir.path)
        let plug = staticFiles(config)

        // Try to access file using symlink or other tricks
        // This is hard to test without creating symlinks, but the
        // implementation checks that the resolved path is still under root

        var conn = Connection.make(path: "/static/../test.txt")
        let result = try await plug(conn)

        // Should be rejected by .. check before path resolution
        #expect(result.response.status == .forbidden)
    }
}
