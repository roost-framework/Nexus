import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import Nexus
import NexusHummingbird
import NexusVapor
import Testing
import Vapor

@Suite("Streaming over TCP", .timeLimit(.minutes(1)))
struct StreamingTransportTests {
    @Test(arguments: Backend.allCases)
    func test_file_slowReader_receivesExactBytes(_ backend: Backend) async throws {
        let url = temporaryFile()
        let payload = Data((0..<(2 * 1_024 * 1_024 + 17)).map { UInt8(truncatingIfNeeded: $0 ^ ($0 >> 16)) })
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try await backend.withServer {
            try $0.sendFile(path: url.path)
        } test: { port in
            let response = try await receive(port: port, delay: .milliseconds(1))
            #expect(response.head?.status == .ok)
            #expect(response.body == payload)
            #expect(response.ended)
        }
    }

    @Test(arguments: Backend.allCases)
    func test_sse_slowReader_receivesEventsAndAutomaticEnd(_ backend: Backend) async throws {
        let events = [SSEEvent(data: "one\ntwo", event: "update", id: "1"), SSEEvent(data: "three", id: "2")]
        try await backend.withServer { conn in
            conn.sseEvent { writer in
                for event in events { try await writer.write(event) }
                try await writer.write(": heartbeat\n\n")
            }
        } test: { port in
            let response = try await receive(port: port, delay: .milliseconds(10))
            #expect(response.head?.headers.first(name: "content-type") == "text/event-stream; charset=utf-8")
            #expect(response.head?.headers.first(name: "cache-control") == "no-cache, no-transform")
            #expect(response.head?.headers.first(name: "x-accel-buffering") == "no")
            #expect(
                String(decoding: response.body, as: UTF8.self) == events.map { $0.formatted() }.joined()
                    + ": heartbeat\n\n")
            #expect(response.ended)
        }
    }

    @Test(arguments: Backend.allCases, ["file", "sse"])
    func test_stream_stalledReaderAndDisconnect_stopsProduction(
        _ backend: Backend, _ kind: String
    ) async throws {
        // A sparse 256 MiB file keeps the fixture cheap while making eager
        // production observable. The client bounds its receive buffer and
        // stops reading after the first body part.
        let url = temporaryFile()
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 256 * 1_024 * 1_024)
        try file.close()
        let state = NIOLockedValueBox(Progress())
        let plug: Plug = { conn in
            var result: Connection
            if kind == "file" {
                result = try conn.sendFile(path: url.path)
            } else {
                result = conn.sseEvent { writer in
                    for index in 0..<4_096 {
                        try await writer.write(SSEEvent(data: String(repeating: "x", count: 65_536), id: "\(index)"))
                    }
                }
            }
            guard case .producer(let produce) = result.responseBody else {
                throw ProbeError.missingProducer
            }
            result.responseBody = .producer { writer in
                defer { state.withLockedValue { $0.finished = true } }
                var recording: any Nexus.ResponseBodyWriter = RecordingWriter(base: writer, state: state)
                do {
                    try await produce(&recording)
                } catch {
                    state.withLockedValue { $0.failed = true }
                    throw error
                }
            }
            return result
        }
        try await backend.withServer(plug: plug) { port in
            try await withSocket(port: port) { inbound, channel in
                var iterator = inbound.makeAsyncIterator()
                while let part = try await iterator.next() {
                    guard case .body = part else { continue }
                    try await Task.sleep(for: .milliseconds(250))
                    let stalled = state.withLockedValue { $0 }
                    #expect(stalled.writes > 0)
                    #expect(
                        stalled.bytes < 32 * 1_024 * 1_024,
                        "A stalled client must stop production well before the 256 MiB response is generated")
                    #expect(!stalled.finished)
                    try await channel.close().get()
                    return
                }
                Issue.record("Expected the first streamed body part")
            }
            let deadline = ContinuousClock.now + .seconds(5)
            while !state.withLockedValue({ $0.finished }) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let stopped = state.withLockedValue { $0 }
            #expect(stopped.finished, "The producer must unwind after the client disconnects")
            #expect(stopped.failed, "Disconnect must reach the producer as a failed write")
            #expect(stopped.bytes < 32 * 1_024 * 1_024)
        }
    }

    @Test(arguments: Backend.allCases)
    func test_producer_error_abortsResponseAndRunsCleanup(_ backend: Backend) async throws {
        let cleanedUp = NIOLockedValueBox(false)
        try await backend.withServer { conn in
            conn.sendChunked { writer in
                defer { cleanedUp.withLockedValue { $0 = true } }
                try await writer.write("partial")
                throw ProbeError.producerFailed
            }
        } test: { port in
            try await withSocket(port: port) { inbound, _ in
                var ended = false
                do {
                    for try await part in inbound {
                        if case .end = part {
                            ended = true
                            break
                        }
                    }
                } catch {
                    // An incomplete chunked response is expected on abort.
                }
                #expect(!ended, "A failed producer must not send a successful HTTP end marker")
            }
            #expect(cleanedUp.withLockedValue { $0 })
        }
    }

    @Test(arguments: Backend.allCases)
    func test_suppressedBodies_doNotStartProducers(_ backend: Backend) async throws {
        try await backend.withServer { conn in
            let status = Int(String((conn.request.path ?? "/200").dropFirst())) ?? 200
            return conn.sendChunked(status: .init(code: status)) { _ in
                Issue.record("HEAD and bodyless responses must not run a producer")
            }
        } test: { port in
            for status in [200, 204, 205, 304] {
                let response = try await receive(port: port, path: "/\(status)", method: status == 200 ? .HEAD : .GET)
                #expect(response.head?.status.code == UInt(status))
                #expect(response.body.isEmpty)
                #expect(response.ended)
            }
        }
    }
}

enum Backend: String, CaseIterable, Sendable {
    case hummingbird
    case vapor

    func withServer(plug: @escaping Plug, test: @escaping @Sendable (Int) async throws -> Void) async throws {
        switch self {
        case .hummingbird:
            let app = Hummingbird.Application(
                responder: NexusHummingbirdAdapter(plug: plug),
                configuration: .init(address: .hostname("127.0.0.1", port: 0))
            )
            try await app.test(.live) { client in
                try await test(try #require(client.port))
            }
        case .vapor:
            let app = try await Vapor.Application.make(.testing)
            app.environment.arguments = ["serve"]
            app.http.server.configuration.hostname = "127.0.0.1"
            app.http.server.configuration.port = 0
            app.middleware.use(NexusVaporAdapter(plug: plug), at: .beginning)
            do {
                try await app.startup()
                try await test(try #require(app.http.server.shared.localAddress?.port))
            } catch {
                try await app.asyncShutdown()
                throw error
            }
            try await app.asyncShutdown()
        }
    }
}

private struct Progress: Sendable {
    var writes = 0
    var bytes = 0
    var finished = false
    var failed = false
}

private struct RecordingWriter: Nexus.ResponseBodyWriter {
    var base: any Nexus.ResponseBodyWriter
    let state: NIOLockedValueBox<Progress>

    mutating func write(_ data: Data) async throws {
        state.withLockedValue {
            $0.writes += 1
            $0.bytes += data.count
        }
        try await base.write(data)
    }
}

private enum ProbeError: Error {
    case missingProducer
    case producerFailed
}

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("nexus-stream-\(UUID().uuidString).bin")
}

private typealias Socket = NIOAsyncChannel<HTTPClientResponsePart, HTTPClientRequestPart>

private func withSocket<Value: Sendable>(
    port: Int,
    path: String = "/",
    method: NIOHTTP1.HTTPMethod = .GET,
    operation:
        @escaping @Sendable (NIOAsyncChannelInboundStream<HTTPClientResponsePart>, any Channel) async throws -> Value
) async throws -> Value {
    let socket: Socket = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
        .channelOption(ChannelOptions.socketOption(.so_rcvbuf), value: 8_192)
        .channelOption(ChannelOptions.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: 16_384))
        .connect(host: "localhost", port: port) { channel in
            channel.eventLoop.makeCompletedFuture {
                try channel.pipeline.syncOperations.addHTTPClientHandlers()
                return try Socket(
                    wrappingChannelSynchronously: channel,
                    configuration: .init(backPressureStrategy: .init(lowWatermark: 1, highWatermark: 2))
                )
            }
        }
    // Bound hung reads even if a regression fails to end/abort the response.
    let timedOut = NIOLockedValueBox(false)
    let timeout = socket.channel.eventLoop.scheduleTask(in: .seconds(10)) {
        timedOut.withLockedValue { $0 = true }
        socket.channel.close(promise: nil)
    }
    defer {
        timeout.cancel()
        if timedOut.withLockedValue({ $0 }) {
            Issue.record("Timed out waiting for the server; a client timeout is not a successful response abort")
        }
    }
    return try await socket.executeThenClose { inbound, outbound in
        let head = HTTPRequestHead(version: .http1_1, method: method, uri: path, headers: ["Host": "localhost"])
        try await outbound.write(.head(head))
        try await outbound.write(.end(nil))
        return try await operation(inbound, socket.channel)
    }
}

private struct WireResponse: Sendable {
    var head: HTTPResponseHead?
    var body = Data()
    var ended = false
}

private func receive(
    port: Int, path: String = "/", method: NIOHTTP1.HTTPMethod = .GET, delay: Duration = .zero
) async throws -> WireResponse {
    try await withSocket(port: port, path: path, method: method) { inbound, _ in
        var response = WireResponse()
        for try await part in inbound {
            switch part {
            case .head(let head): response.head = head
            case .body(let buffer):
                response.body.append(contentsOf: buffer.readableBytesView)
                if delay > .zero { try await Task.sleep(for: delay) }
            case .end:
                response.ended = true
                return response
            }
        }
        return response
    }
}
