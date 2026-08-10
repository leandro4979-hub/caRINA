import Foundation

public enum IdempotencyError: Error, Sendable, Equatable {
    case missingKey
    case alreadyReserved(String)
}

/// In-memory at-most-once reservation store. A reservation is intentionally
/// never released after execution failure. Retry semantics must create a new
/// authorized attempt under policy rather than silently reusing authority.
public actor IdempotencyStore {
    private var reservedKeys: Set<String> = []

    public init() {}

    public func reserve(_ key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw IdempotencyError.missingKey
        }
        guard reservedKeys.insert(normalized).inserted else {
            throw IdempotencyError.alreadyReserved(normalized)
        }
    }

    public func contains(_ key: String) -> Bool {
        reservedKeys.contains(key.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
