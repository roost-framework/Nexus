import Foundation
import HTTPTypes
import Testing

@testable import Nexus
@testable import NexusTest

@Suite("Compression Plug")
struct CompressionParityTests {

    // Compression hooks into beforeSend, so we run: plug → result → runBeforeSend() → final
    private func compress(
        _ conn: Connection,
        algorithms: [Compression.Algorithm] = [.gzip, .deflate],
        minimumLength: Int = 1024
    ) async throws -> Connection {
        let plug = Compression(algorithms: algorithms, minimumLength: minimumLength)
        let registered = try await plug.call(conn)
        return registered.runBeforeSend()
    }

    // Payload large enough to exceed default minimumLength
    private func largeBody(_ size: Int = 2048) -> Data {
        Data(String(repeating: "a", count: size).utf8)
    }

    // MARK: - Algorithm Selection

    @Test("gzip encoding when client sends Accept-Encoding: gzip")
    func gzipEncoding() async throws {
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip")
            ]))
        conn.responseBody = .buffered(largeBody())

        let result = try await compress(conn)

        guard case .buffered(let data) = result.responseBody else {
            Issue.record("Expected .buffered body")
            return
        }
        let encoding = result.getRespHeader("Content-Encoding")
        #expect(encoding == "gzip")
        #expect(data.count < largeBody().count)
    }

    @Test("deflate encoding when client sends Accept-Encoding: deflate")
    func deflateEncoding() async throws {
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "deflate")
            ]))
        conn.responseBody = .buffered(largeBody())

        let result = try await compress(conn, algorithms: [.deflate])

        let encoding = result.getRespHeader("Content-Encoding")
        #expect(encoding == "deflate")
    }

    @Test("gzip preferred over deflate when both accepted")
    func gzipPreferredOverDeflate() async throws {
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip, deflate")
            ]))
        conn.responseBody = .buffered(largeBody())

        let result = try await compress(conn)

        #expect(result.getRespHeader("Content-Encoding") == "gzip")
    }

    // MARK: - Minimum Length

    @Test("body below minimumLength passes through uncompressed")
    func belowMinimumLength() async throws {
        let smallData = Data("small".utf8)
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip")
            ]))
        conn.responseBody = .buffered(smallData)

        let result = try await compress(conn, minimumLength: 1024)

        guard case .buffered(let data) = result.responseBody else {
            Issue.record("Expected .buffered body")
            return
        }
        #expect(data == smallData)
        #expect(result.getRespHeader("Content-Encoding") == nil)
    }

    @Test("body exactly at minimumLength is compressed")
    func exactlyAtMinimumLength() async throws {
        let body = largeBody(100)
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip")
            ]))
        conn.responseBody = .buffered(body)

        let result = try await compress(conn, minimumLength: 100)

        #expect(result.getRespHeader("Content-Encoding") == "gzip")
    }

    // MARK: - Streaming Bodies

    @Test("streaming body passes through unchanged")
    func streamingBodyPassThrough() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(largeBody())
            continuation.finish()
        }
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip")
            ]))
        conn.responseBody = .stream(stream)

        let result = try await compress(conn)

        if case .stream = result.responseBody {
            #expect(result.getRespHeader("Content-Encoding") == nil)
        } else {
            Issue.record("Expected streaming body to be unchanged")
        }
    }

    // MARK: - No Compression Cases

    @Test("no Accept-Encoding header leaves body unchanged")
    func noAcceptEncoding() async throws {
        let body = largeBody()
        var conn = Connection.make()
        conn.responseBody = .buffered(body)

        let result = try await compress(conn)

        guard case .buffered(let data) = result.responseBody else {
            Issue.record("Expected .buffered body")
            return
        }
        #expect(data == body)
        #expect(result.getRespHeader("Content-Encoding") == nil)
    }

    @Test("empty body passes through unchanged")
    func emptyBody() async throws {
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip")
            ]))
        conn.responseBody = .empty

        let result = try await compress(conn)

        if case .empty = result.responseBody {
            #expect(result.getRespHeader("Content-Encoding") == nil)
        } else {
            Issue.record("Expected .empty body")
        }
    }

    @Test("identity encoding in Accept-Encoding leaves body unchanged")
    func identityEncoding() async throws {
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "identity")
            ]))
        conn.responseBody = .buffered(largeBody())

        let result = try await compress(conn)

        #expect(result.getRespHeader("Content-Encoding") == nil)
    }

    // MARK: - Headers

    @Test("Content-Length is cleared after compression")
    func contentLengthCleared() async throws {
        let body = largeBody()
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip")
            ]))
        conn.responseBody = .buffered(body)
        conn.response.headerFields[.contentLength] = "\(body.count)"

        let result = try await compress(conn)

        #expect(result.response.headerFields[.contentLength] == nil)
    }

    @Test("compression does not modify request headers")
    func requestHeadersUntouched() async throws {
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip"),
                HTTPField(name: .accept, value: "application/json"),
            ]))
        conn.responseBody = .buffered(largeBody())

        let result = try await compress(conn)

        #expect(result.getReqHeader(.accept) == "application/json")
    }

    // MARK: - beforeSend Registration

    @Test("compression is registered as beforeSend hook")
    func registeredAsBeforeSend() async throws {
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip")
            ]))
        conn.responseBody = .buffered(largeBody())

        let plug = Compression()
        let registered = try await plug.call(conn)

        // beforeSend is registered but not yet executed
        #expect(!registered.beforeSend.isEmpty)
        #expect(registered.getRespHeader("Content-Encoding") == nil)
    }

    @Test("compression executes after downstream plug sets the body")
    func compressesBodySetDownstream() async throws {
        let body = largeBody()
        var conn = Connection.make(
            headers: HTTPFields([
                HTTPField(name: .acceptEncoding, value: "gzip")
            ]))

        // Simulate: compression registered first, body set later downstream
        let plug = Compression()
        var registered = try await plug.call(conn)
        registered.responseBody = .buffered(body)

        let final = registered.runBeforeSend()

        #expect(final.getRespHeader("Content-Encoding") == "gzip")
    }
}
