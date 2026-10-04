extension Connection {
    /// Stores framework metadata separately from application assigns.
    /// Keys should be prefixed with the library name to avoid collisions.
    /// - Parameters:
    ///   - key: The framework metadata key.
    ///   - value: The value to store.
    /// - Returns: A new connection with the metadata assigned.
    public func putPrivate(_ key: String, value: any Sendable) -> Connection {
        var copy = self
        copy.privateData[key] = value
        return copy
    }

    /// Merges framework metadata; supplied values replace existing values for the same keys.
    /// - Parameter values: Metadata to merge.
    /// - Returns: A new connection with the merged metadata.
    public func mergePrivate(_ values: [String: any Sendable]) -> Connection {
        var copy = self
        copy.privateData.merge(values) { _, new in new }
        return copy
    }
}
