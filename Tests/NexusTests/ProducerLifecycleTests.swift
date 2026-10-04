import Foundation
import HTTPTypes
import Nexus
import Testing

@Suite("Producer lifecycle", .timeLimit(.minutes(1)))
struct ProducerLifecycleTests {
    private func connection() -> Connection {
        Connection(request: HTTPRequest(method: .get, scheme: "http", authority: "localhost", path: "/"))
    }

    @Test func test_sendChunked_unconsumed_doesNotStartProducer() {
        _ = connection().sendChunked { _ in
            Issue.record("Creating or discarding a response must not start its producer")
        }
    }

    @Test func test_sendChunked_failedWrite_unwindsProducer() async throws {
        struct WriteFailure: Error {}
        let (cleanup, completed) = AsyncStream<Void>.makeStream()
        let body = connection().sendChunked { writer in
            defer {
                completed.yield(())
                completed.finish()
            }
            try await writer.write("first")
            Issue.record("A failed write must stop this producer")
        }.responseBody
        guard case .producer(let produce) = body else {
            Issue.record("Expected producer body")
            return
        }
        var writer: any ResponseBodyWriter = ClosureWriter { _ in throw WriteFailure() }
        await #expect(throws: WriteFailure.self) { try await produce(&writer) }
        var iterator = cleanup.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    @Test func test_sendChunked_cancelledWrite_runsCleanup() async throws {
        let (entered, enteredSource) = AsyncStream<Void>.makeStream()
        let (cleanup, cleanupSource) = AsyncStream<Void>.makeStream()
        let body = connection().sendChunked { writer in
            defer {
                cleanupSource.yield(())
                cleanupSource.finish()
            }
            try await writer.write("first")
            Issue.record("Cancellation must stop this producer")
        }.responseBody
        guard case .producer(let produce) = body else {
            Issue.record("Expected producer body")
            return
        }
        let task = Task {
            var writer: any ResponseBodyWriter = ClosureWriter { _ in
                enteredSource.yield(())
                try await Task.sleep(for: .seconds(30))
            }
            try await produce(&writer)
        }
        defer { task.cancel() }
        var iterator = entered.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        var cleanupIterator = cleanup.makeAsyncIterator()
        #expect(await cleanupIterator.next() != nil)
    }

    @Test func test_sendFile_stalledWrite_doesNotReadAhead() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("aaaabbbbcccc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let body = try connection().sendFile(path: url.path, chunkSize: 4).responseBody
        guard case .producer(let produce) = body else {
            Issue.record("Expected producer body")
            return
        }
        let (entered, enteredSource) = AsyncStream<Void>.makeStream()
        let (release, releaseSource) = AsyncStream<Void>.makeStream()
        let (chunks, chunkSource) = AsyncStream<Data>.makeStream()
        let task = Task {
            defer { chunkSource.finish() }
            var writer: any ResponseBodyWriter = ClosureWriter { data in
                chunkSource.yield(data)
                enteredSource.yield(())
                var iterator = release.makeAsyncIterator()
                _ = await iterator.next()
                try Task.checkCancellation()
            }
            try await produce(&writer)
        }
        defer {
            task.cancel()
            releaseSource.finish()
        }
        var iterator = entered.makeAsyncIterator()
        _ = await iterator.next()
        // Change the unread region while the first write is suspended. Reading
        // ahead would retain the old tail and incorrectly deliver bbbb/cccc.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 4)
        try handle.close()
        releaseSource.finish()
        try await task.value
        var received = Data()
        for await chunk in chunks { received.append(chunk) }
        #expect(received == Data("aaaa".utf8))
    }

    @Test(arguments: [0, -1])
    func test_sendFile_invalidChunkSize_rejectsConfiguration(_ size: Int) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("contents".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: NexusHTTPError.self) {
            try connection().sendFile(path: url.path, chunkSize: size)
        }
    }

    @Test func test_sendFile_removedBeforeDelivery_opensLazilyAndFails() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("contents".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let body = try connection().sendFile(path: url.path).responseBody
        guard case .producer(let produce) = body else {
            Issue.record("Expected producer body")
            return
        }
        try FileManager.default.removeItem(at: url)
        await #expect(throws: (any Error).self) {
            _ = try await collectProducer(produce)
        }
    }

    @Test func test_sseEvent_returnsWithoutFinish_haltsAndFormatsEvents() async throws {
        let result = connection().sseEvent { writer in
            try await writer.write(SSEEvent(data: "one\ntwo", event: "update", id: "7", retry: 500))
            try await writer.write(": heartbeat\n\n")
        }
        #expect(result.isHalted)
        guard case .producer(let produce) = result.responseBody else {
            Issue.record("Expected producer body")
            return
        }
        let chunks = try await collectProducer(produce)
        #expect(
            chunks == [
                Data("id: 7\nevent: update\nretry: 500\ndata: one\ndata: two\n\n".utf8),
                Data(": heartbeat\n\n".utf8),
            ])
    }
}

private struct ClosureWriter: ResponseBodyWriter {
    let operation: @Sendable (Data) async throws -> Void

    func write(_ data: Data) async throws {
        try await operation(data)
    }
}
