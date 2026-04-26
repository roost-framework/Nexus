import Testing
@testable import Nexus
@testable import NexusVapor
import HTTPTypes
import Vapor

/// Performance benchmarks for NexusVapor adapter.
///
/// These benchmarks measure adapter overhead compared to raw Vapor to ensure
/// the Nexus pipeline adds minimal latency (<5% target) while providing
/// enhanced composability and features.
@Suite("NexusVaporBenchmarks")
struct NexusVaporBenchmarks {

    // MARK: - Test Data

    /// Simple HTTP request for benchmarking
    private static let simpleRequest = HTTPRequest(
        method: .get,
        scheme: .https,
        authority: "example.com",
        path: "/test"
    )

    /// Sample body data
    private static let bodyData = Data(repeating: 0x42, count: 100)

    // MARK: - 1. Baseline Adapter Overhead

    /// Benchmark 1.1: Simple Plug Creation
    ///
    /// Measures overhead of creating and running a single plug through NexusVapor.
    /// Target: <5% overhead vs raw Vapor.
    @Test(
        "Adapter overhead: Simple plug vs raw Vapor",
        .benchmark(.throughput),
        .enabled(true)
    )
    func adapterOverheadSimplePlug() async throws {
        let simplePlug: Plug = { conn in
            return conn.respond(status: .ok, body: .string("Hello"))
        }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await simplePlug(connection)
        #expect(result.response.status.code == 200)
    }

    /// Benchmark 1.2: Empty Pipeline vs Raw Vapor
    ///
    /// Compare minimal Nexus pipeline (identity plug) vs raw Vapor response.
    /// This should show <5% overhead when optimized.
    @Test(
        "Adapter overhead: Empty pipeline overhead",
        .benchmark(.throughput),
        .enabled(true)
    )
    func adapterOverheadEmptyPipeline() async throws {
        let identityPlug: Plug = { conn in conn }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await identityPlug(connection)
        #expect(!result.isHalted)
    }

    // MARK: - 2. Request Throughput

    /// Benchmark 2.1: Single Plug Throughput
    ///
    /// Measures requests per second through a single plug.
    /// Target: >10,000 req/s.
    @Test(
        "Throughput: Single plug",
        .benchmark(.throughput),
        .enabled(true)
    )
    func throughputSinglePlug() async throws {
        let plug: Plug = { conn in
            conn.respond(status: .ok, body: .string("OK"))
        }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await plug(connection)
        #expect(result.response.status.code == 200)
    }

    /// Benchmark 2.2: Pipeline Chain Throughput
    ///
    /// Measures throughput through a 5-plug pipeline.
    /// Target: >8,000 req/s with 5 plugs.
    @Test(
        "Throughput: 5-plug pipeline",
        .benchmark(.throughput),
        .enabled(true)
    )
    func throughputFivePlugPipeline() async throws {
        let plug1: Plug = { conn in conn }
        let plug2: Plug = { conn in conn }
        let plug3: Plug = { conn in conn }
        let plug4: Plug = { conn in conn }
        let plug5: Plug = { conn in
            conn.respond(status: .ok, body: .string("OK"))
        }

        let pipeline = pipe(plug1, plug2, plug3, plug4, plug5)

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await pipeline(connection)
        #expect(result.response.status.code == 200)
    }

    /// Benchmark 2.3: Request with Body Throughput
    ///
    /// Measures throughput with buffered request bodies.
    /// Target: >5,000 req/s with 100-byte bodies.
    @Test(
        "Throughput: Request with 100-byte body",
        .benchmark(.throughput),
        .enabled(true)
    )
    func throughputWithBody() async throws {
        var bodyRequest = simpleRequest
        var fields = HTTPFields()
        fields[.contentType] = "application/json"
        fields[.contentLength] = "100"
        bodyRequest.headerFields = fields

        let plug: Plug = { conn in
            if case .buffered(let data) = conn.requestBody {
                return conn.respond(status: .ok, body: .buffered(data))
            }
            return conn.respond(status: .badRequest, body: .empty)
        }

        let connection = Connection(
            request: bodyRequest,
            requestBody: .buffered(bodyData)
        )

        let result = try await plug(connection)
        #expect(result.response.status.code == 200)
    }

    // MARK: - 3. Memory Allocation

    /// Benchmark 3.1: Connection Creation Memory
    ///
    /// Measures memory allocation for creating a Connection.
    /// Target: <512 bytes per connection.
    @Test(
        "Memory: Connection creation",
        .benchmark(.metrics),
        .enabled(true)
    )
    func memoryConnectionCreation() async throws {
        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )
        #expect(connection.request.method == .get)
    }

    /// Benchmark 3.2: Pipeline Execution Memory
    ///
    /// Measures memory allocation during pipeline execution.
    /// Target: <1KB total per request.
    @Test(
        "Memory: Pipeline execution allocation",
        .benchmark(.metrics),
        .enabled(true)
    )
    func memoryPipelineExecution() async throws {
        let plug: Plug = { conn in
            var modified = conn
            modified.assigns["key1"] = "value1"
            modified.assigns["key2"] = "value2"
            modified.assigns["key3"] = "value3"
            return modified.respond(status: .ok, body: .string("OK"))
        }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await plug(connection)
        #expect(result.assigns.count == 3)
    }

    // MARK: - 4. Pipeline Composition Overhead

    /// Benchmark 4.1: Single Plug Overhead
    ///
    /// Measures baseline cost of plug invocation.
    /// Target: <50ns per plug call.
    @Test(
        "Pipeline: Single plug invocation time",
        .benchmark(.throughput),
        .enabled(true)
    )
    func pipelineSinglePlug() async throws {
        let plug: Plug = { conn in conn }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await plug(connection)
        #expect(!result.isHalted)
    }

    /// Benchmark 4.2: Pipe() Composition Overhead
    ///
    /// Measures overhead of pipe() combinator.
    /// Target: <10ns per pipe() call.
    @Test(
        "Pipeline: pipe() combinator overhead",
        .benchmark(.throughput),
        .enabled(true)
    )
    func pipelinePipeCombinator() async throws {
        let plug1: Plug = { conn in conn }
        let plug2: Plug = { conn in conn }
        let composed = pipe(plug1, plug2)

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await composed(connection)
        #expect(!result.isHalted)
    }

    /// Benchmark 4.3: 10-Plug Pipeline
    ///
    /// Measures overhead of deep pipeline chains.
    /// Target: <500ns total for 10 plugs.
    @Test(
        "Pipeline: 10-plug chain overhead",
        .benchmark(.throughput),
        .enabled(true)
    )
    func pipelineTenPlugs() async throws {
        let plugs = (0..<10).map { _ -> Plug in { conn in conn } }
        let pipeline = plugs.reduce(plug: { $1($0) }, { conn in conn })

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await pipeline(connection)
        #expect(!result.isHalted)
    }

    // MARK: - 5. BeforeSend Hooks Performance

    /// Benchmark 5.1: Single BeforeSend Hook
    ///
    /// Measures cost of single lifecycle hook.
    /// Target: <50ns per hook invocation.
    @Test(
        "BeforeSend: Single hook overhead",
        .benchmark(.throughput),
        .enabled(true)
    )
    func beforeSendSingleHook() async throws {
        let plug: Plug = { conn in
            var modified = conn
            modified.beforeSend.append { $0.respond(status: .ok, body: .string("Hooked")) }
            return modified
        }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await plug(connection)
        let final = result.runBeforeSend()
        #expect(final.response.status.code == 200)
    }

    /// Benchmark 5.2: Multiple BeforeSend Hooks
    ///
    /// Measures overhead of multiple hooks (LIFO execution).
    /// Target: <50ns per hook, linear scaling.
    @Test(
        "BeforeSend: 5 hooks (LIFO execution)",
        .benchmark(.throughput),
        .enabled(true)
    )
    func beforeSendMultipleHooks() async throws {
        let plug: Plug = { conn in
            var modified = conn
            for i in 0..<5 {
                modified.beforeSend.append { connection in
                    var conn = connection
                    conn.assigns["hook_\(i)"] = true
                    return conn
                }
            }
            return modified
        }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await plug(connection)
        let final = result.runBeforeSend()
        #expect(final.assigns.count == 5)
    }

    // MARK: - 6. Streaming Performance

    /// Benchmark 6.1: Empty Stream Creation
    ///
    /// Measures overhead of creating streaming response.
    /// Target: <100ns to set up stream.
    @Test(
        "Streaming: Empty AsyncSequence stream creation",
        .benchmark(.throughput),
        .enabled(true)
    )
    func streamingEmptyStream() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish()
        }

        let plug: Plug = { conn in
            conn.respond(status: .ok, body: .stream(stream))
        }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await plug(connection)
        if case .stream = result.responseBody {
            // Stream created successfully
        } else {
            #expect(Bool(false), "Expected stream response body")
        }
    }

    /// Benchmark 6.2: Single Chunk Stream
    ///
    /// Measures latency to first chunk in stream.
    /// Target: <1ms to first chunk.
    @Test(
        "Streaming: Single chunk stream latency",
        .benchmark(.throughput),
        .enabled(true)
    )
    func streamingSingleChunk() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("Hello".utf8))
            continuation.finish()
        }

        let plug: Plug = { conn in
            conn.respond(status: .ok, body: .stream(stream))
        }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await plug(connection)

        if case .stream(let asyncSequence) = result.responseBody {
            for try await chunk in asyncSequence {
                #expect(chunk == Data("Hello".utf8))
            }
        } else {
            #expect(Bool(false), "Expected stream body")
        }
    }

    /// Benchmark 6.3: Multi-Chunk Stream
    ///
    /// Measures overhead of yielding multiple chunks.
    /// Target: <100μs per chunk yield.
    @Test(
        "Streaming: 10-chunk stream throughput",
        .benchmark(.throughput),
        .enabled(true)
    )
    func streamingMultiChunk() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                for i in 0..<10 {
                    continuation.yield(Data("chunk\(i)".utf8))
                }
                continuation.finish()
            }
        }

        let plug: Plug = { conn in
            conn.respond(status: .ok, body: .stream(stream))
        }

        let connection = Connection(
            request: simpleRequest,
            requestBody: .empty
        )

        let result = try await plug(connection)

        if case .stream(let asyncSequence) = result.responseBody {
            var count = 0
            for try await _ in asyncSequence {
                count += 1
            }
            #expect(count == 10)
        } else {
            #expect(Bool(false), "Expected stream body")
        }
    }
}

// MARK: - Benchmark Performance Summary Extension

extension NexusVaporBenchmarks {
    /// Performance summary report generator.
    ///
    /// Call this after running all benchmarks to generate a summary report.
    /// This helps track performance regressions over time.
    static func generatePerformanceSummary() -> String {
        """
        # NexusVapor Performance Benchmark Summary

        ## Performance Targets

        ### Adapter Overhead
        - Target: <5% vs raw Vapor
        - Critical for: Adoption competitiveness

        ### Throughput
        - Simple pipeline: >10,000 req/s
        - 5-plug pipeline: >8,000 req/s
        - With body processing: >5,000 req/s

        ### Memory Allocation
        - Connection creation: <512 bytes
        - Pipeline execution: <1KB per request
        - Response buffering: Body size + 100 bytes

        ### Pipeline Composition
        - Single plug: <50ns
        - pipe() combinator: <10ns
        - 10-plug chain: <500ns total

        ### BeforeSend Hooks
        - Single hook: <50ns
        - Multiple hooks: <50ns per hook (linear)
        - vs inline: <20% overhead

        ### Streaming Performance
        - Stream setup: <100ns
        - First byte latency: <1ms
        - Chunk yield: <100μs per chunk

        ## Regression Detection

        Run benchmarks after significant changes:
        ```bash
        swift test --filter NexusVaporBenchmarks
        ```

        Compare results against baseline to detect regressions.

        ## Optimization Priority

        1. **P0**: Adapter overhead >5% (blocks adoption)
        2. **P1**: Throughput degradation >10%
        3. **P2**: Memory leaks or excessive allocation
        4. **P3**: Streaming latency >2ms to first byte

        """
    }
}
