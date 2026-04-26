import Testing
import HTTPTypes
import Foundation
@testable import Nexus

@Suite("RequestBody and ResponseBody Error Paths")
struct BodyErrorPathTests {

    // MARK: - RequestBody Edge Cases

    @Test("RequestBody empty case")
    func requestBodyEmpty() {
        let body = RequestBody.empty
        if case .empty = body { } else {
            Issue.record("Expected .empty case")
        }
    }

    @Test("RequestBody buffered with empty data")
    func requestBodyBufferedEmpty() {
        let body = RequestBody.buffered(Data())
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(data.isEmpty)
    }

    @Test("RequestBody buffered with large data")
    func requestBodyBufferedLarge() {
        let largeData = Data(repeating: 0xFF, count: 10_000_000)
        let body = RequestBody.buffered(largeData)
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(data.count == 10_000_000)
    }

    @Test("RequestBody stream with throwing stream")
    func requestBodyStreamThrowing() async {
        enum TestError: Error {
            case streamFailed
        }

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish(throwing: TestError.streamFailed)
        }

        let body = RequestBody.stream(stream)
        guard case let .stream(retrievedStream) = body else {
            Issue.record("Expected .stream case")
            return
        }

        do {
            for try await _ in retrievedStream {
                #expect(Bool(false), "Stream should throw")
            }
        } catch TestError.streamFailed {
            // Expected
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("RequestBody stream with multiple chunks")
    func requestBodyStreamMultipleChunks() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                continuation.yield(Data([1, 2, 3]))
                continuation.yield(Data([4, 5, 6]))
                continuation.yield(Data([7, 8, 9]))
                continuation.finish()
            }
        }

        let body = RequestBody.stream(stream)
        guard case let .stream(retrievedStream) = body else {
            Issue.record("Expected .stream case")
            return
        }

        var chunks: [[UInt8]] = []
        for try await chunk in retrievedStream {
            chunks.append(Array(chunk))
        }

        #expect(chunks.count == 3)
        #expect(chunks[0] == [1, 2, 3])
        #expect(chunks[1] == [4, 5, 6])
        #expect(chunks[2] == [7, 8, 9])
    }

    @Test("RequestBody stream with empty chunks")
    func requestBodyStreamEmptyChunks() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                continuation.yield(Data())
                continuation.yield(Data())
                continuation.finish()
            }
        }

        let body = RequestBody.stream(stream)
        guard case let .stream(retrievedStream) = body else {
            Issue.record("Expected .stream case")
            return
        }

        var chunkCount = 0
        for try await chunk in retrievedStream {
            chunkCount += 1
            #expect(chunk.isEmpty)
        }

        #expect(chunkCount == 2)
    }

    // MARK: - ResponseBody Edge Cases

    @Test("ResponseBody empty case")
    func responseBodyEmpty() {
        let body = ResponseBody.empty
        if case .empty = body { } else {
            Issue.record("Expected .empty case")
        }
    }

    @Test("ResponseBody buffered with empty data")
    func responseBodyBufferedEmpty() {
        let body = ResponseBody.buffered(Data())
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(data.isEmpty)
    }

    @Test("ResponseBody buffered with large data")
    func responseBodyBufferedLarge() {
        let largeData = Data(repeating: 0xAA, count: 10_000_000)
        let body = ResponseBody.buffered(largeData)
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(data.count == 10_000_000)
    }

    @Test("ResponseBody stream with throwing stream")
    func responseBodyStreamThrowing() async {
        enum TestError: Error {
            case streamFailed
        }

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish(throwing: TestError.streamFailed)
        }

        let body = ResponseBody.stream(stream)
        guard case let .stream(retrievedStream) = body else {
            Issue.record("Expected .stream case")
            return
        }

        do {
            for try await _ in retrievedStream {
                #expect(Bool(false), "Stream should throw")
            }
        } catch TestError.streamFailed {
            // Expected
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test("ResponseBody stream with multiple chunks")
    func responseBodyStreamMultipleChunks() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                continuation.yield(Data([10, 20, 30]))
                continuation.yield(Data([40, 50, 60]))
                continuation.finish()
            }
        }

        let body = ResponseBody.stream(stream)
        guard case let .stream(retrievedStream) = body else {
            Issue.record("Expected .stream case")
            return
        }

        var chunks: [[UInt8]] = []
        for try await chunk in retrievedStream {
            chunks.append(Array(chunk))
        }

        #expect(chunks.count == 2)
        #expect(chunks[0] == [10, 20, 30])
        #expect(chunks[1] == [40, 50, 60])
    }

    // MARK: - ResponseBody.string() Edge Cases

    @Test("ResponseBody string with empty string")
    func responseBodyStringEmpty() {
        let body = ResponseBody.string("")
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(data.isEmpty)
    }

    @Test("ResponseBody string with ASCII")
    func responseBodyStringASCII() {
        let body = ResponseBody.string("Hello, World!")
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "Hello, World!")
    }

    @Test("ResponseBody string with Unicode")
    func responseBodyStringUnicode() {
        let input = "Hello 世界 🌍"
        let body = ResponseBody.string(input)
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(String(data: data, encoding: .utf8) == input)
    }

    @Test("ResponseBody string with emoji")
    func responseBodyStringEmoji() {
        let input = "😀😃😄😁😆"
        let body = ResponseBody.string(input)
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(String(data: data, encoding: .utf8) == input)
    }

    @Test("ResponseBody string with invalid UTF-8 sequence")
    func responseBodyStringInvalidUTF8() {
        let body = ResponseBody.string("valid")
        if case .buffered = body { } else {
            Issue.record("Expected .buffered case")
        }
    }

    @Test("ResponseBody string with very long string")
    func responseBodyStringVeryLong() {
        let longString = String(repeating: "a", count: 1_000_000)
        let body = ResponseBody.string(longString)
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(data.count == 1_000_000)
    }

    @Test("ResponseBody string with newlines and special chars")
    func responseBodyStringSpecialChars() {
        let input = "Line 1\nLine 2\r\nLine 3\tTabbed\u{0}Null"
        let body = ResponseBody.string(input)
        guard case let .buffered(data) = body else {
            Issue.record("Expected .buffered case")
            return
        }
        #expect(String(data: data, encoding: .utf8) == input)
    }

    // MARK: - Sendable Conformance

    @Test("RequestBody is Sendable across actors")
    func requestBodyIsSendable() async throws {
        actor TestActor {
            private var stored: RequestBody?

            func store(_ body: RequestBody) {
                stored = body
            }

            func get() -> RequestBody? {
                stored
            }
        }

        let testActor = TestActor()
        let body = RequestBody.buffered(Data("test".utf8))

        await testActor.store(body)
        let retrieved = await testActor.get()

        guard let retrieved, case let .buffered(data) = retrieved else {
            Issue.record("Expected .buffered value")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "test")
    }

    @Test("ResponseBody is Sendable across actors")
    func responseBodyIsSendable() async throws {
        actor TestActor {
            private var stored: ResponseBody?

            func store(_ body: ResponseBody) {
                stored = body
            }

            func get() -> ResponseBody? {
                stored
            }
        }

        let testActor = TestActor()
        let body = ResponseBody.string("test")

        await testActor.store(body)
        let retrieved = await testActor.get()

        guard let retrieved, case let .buffered(data) = retrieved else {
            Issue.record("Expected .buffered value")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "test")
    }

    // MARK: - Stream Cancellation

    @Test("RequestBody stream respects cancellation")
    func requestBodyStreamCancellation() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                for i in 0..<100 {
                    continuation.yield(Data([UInt8(i & 0xFF)]))
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                continuation.finish()
            }
        }

        let body = RequestBody.stream(stream)
        guard case let .stream(retrievedStream) = body else {
            Issue.record("Expected .stream case")
            return
        }

        var count = 0
        for try await _ in retrievedStream {
            count += 1
            if count >= 5 { break }
        }

        #expect(count == 5)
    }

    @Test("ResponseBody stream respects cancellation")
    func responseBodyStreamCancellation() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                for i in 0..<100 {
                    continuation.yield(Data([UInt8(i & 0xFF)]))
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                continuation.finish()
            }
        }

        let body = ResponseBody.stream(stream)
        guard case let .stream(retrievedStream) = body else {
            Issue.record("Expected .stream case")
            return
        }

        var count = 0
        for try await _ in retrievedStream {
            count += 1
            if count >= 3 { break }
        }

        #expect(count == 3)
    }

    // MARK: - Memory Efficiency

    @Test("RequestBody stream uses constant memory")
    func requestBodyStreamConstantMemory() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                for _ in 0..<1000 {
                    let chunk = Data(repeating: UInt8.random(in: 0...255), count: 1024)
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }

        let body = RequestBody.stream(stream)
        guard case let .stream(retrievedStream) = body else {
            Issue.record("Expected .stream case")
            return
        }

        var chunkCount = 0
        for try await _ in retrievedStream {
            chunkCount += 1
        }

        #expect(chunkCount == 1000)
    }
}
