import Foundation
import Testing

@testable import Nexus
@testable import NexusTest

@Suite("Timeout Plug")
struct TimeoutParityTests {

    // MARK: - Normal Completion

    @Test("fast plug completes without triggering timeout")
    func fastPlugCompletes() async throws {
        let timeout = Timeout(seconds: 5)
        let plug: Plug = { conn in conn.respond(status: .ok) }
        let conn = Connection.make()

        let result = try await timeout.wrap(plug)(conn)

        #expect(result.response.status == .ok)
    }

    @Test("plug result is returned intact when within timeout")
    func resultIntact() async throws {
        let timeout = Timeout(seconds: 5)
        let plug: Plug = { conn in
            conn.respond(status: .created, body: .string("done"))
        }
        let conn = Connection.make()

        let result = try await timeout.wrap(plug)(conn)

        #expect(result.response.status == .created)
        guard case .buffered(let data) = result.responseBody else {
            Issue.record("Expected .buffered body")
            return
        }
        #expect(String(data: data, encoding: .utf8) == "done")
    }

    @Test("timeout with nanoseconds initializer")
    func nanosecondInit() async throws {
        let timeout = Timeout(nanoseconds: 5_000_000_000)
        let plug: Plug = { conn in conn.respond(status: .ok) }
        let conn = Connection.make()
        let result = try await timeout.wrap(plug)(conn)
        #expect(result.response.status == .ok)
    }

    // MARK: - Timeout Firing

    @Test("slow plug throws TimeoutError")
    func slowPlugThrowsTimeout() async throws {
        let timeout = Timeout(nanoseconds: 1_000_000)  // 1ms
        let slowPlug: Plug = { conn in
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            return conn.respond(status: .ok)
        }
        let conn = Connection.make()

        await #expect(throws: Timeout.TimeoutError.self) {
            try await timeout.wrap(slowPlug)(conn)
        }
    }

    @Test("timeout error is distinct type (not generic Error)")
    func timeoutErrorType() async {
        let timeout = Timeout(nanoseconds: 1_000_000)
        let slowPlug: Plug = { conn in
            try await Task.sleep(nanoseconds: 100_000_000)
            return conn.respond(status: .ok)
        }
        let conn = Connection.make()
        var caughtTimeout = false
        do {
            _ = try await timeout.wrap(slowPlug)(conn)
        } catch is Timeout.TimeoutError {
            caughtTimeout = true
        } catch {}
        #expect(caughtTimeout)
    }

    // MARK: - Composition with onError

    @Test("combined with onError produces timeout response")
    func combinedWithOnError() async throws {
        let timeout = Timeout(nanoseconds: 1_000_000)
        let slowPlug: Plug = { conn in
            try await Task.sleep(nanoseconds: 100_000_000)
            return conn.respond(status: .ok)
        }
        let timedApp = onError(timeout.wrap(slowPlug)) { conn, error in
            if error is Timeout.TimeoutError {
                return conn.respond(status: .serviceUnavailable, body: .string("timed out"))
            }
            return conn.respond(status: .internalServerError)
        }
        let conn = Connection.make()
        let result = try await timedApp(conn)
        #expect(result.response.status == .serviceUnavailable)
    }

    // MARK: - Halted Connections

    @Test("halted connection returned as-is before timeout")
    func haltedConnectionPassesThrough() async throws {
        let timeout = Timeout(seconds: 5)
        let haltingPlug: Plug = { conn in
            conn.respond(status: .forbidden)
        }
        let conn = Connection.make()
        let result = try await timeout.wrap(haltingPlug)(conn)
        #expect(result.response.status == .forbidden)
        #expect(result.isHalted)
    }

    // MARK: - Multiple Wraps

    @Test("can wrap any plug including pipelines")
    func wrapsComposedPipeline() async throws {
        let timeout = Timeout(seconds: 5)
        let step1: Plug = { conn in conn.assign(key: "step", value: 1) }
        let step2: Plug = { conn in conn.respond(status: .ok) }
        let composed = pipe(step1, step2)
        let conn = Connection.make()
        let result = try await timeout.wrap(composed)(conn)
        #expect(result.response.status == .ok)
    }
}
