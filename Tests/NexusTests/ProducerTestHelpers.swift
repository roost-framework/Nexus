import Foundation
import Nexus

/// A synchronous collector scoped to a producer invocation, never shared across tasks.
private final class CollectingBodyWriter: ResponseBodyWriter {
    var chunks: [Data] = []

    func write(_ data: Data) async throws {
        try Task.checkCancellation()
        chunks.append(data)
    }
}

func collectProducer(
    _ produce: @Sendable (inout any ResponseBodyWriter) async throws -> Void
) async throws -> [Data] {
    let collector = CollectingBodyWriter()
    var writer: any ResponseBodyWriter = collector
    try await produce(&writer)
    return collector.chunks
}
