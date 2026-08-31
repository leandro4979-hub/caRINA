import Foundation

public enum IdempotencyError: Error, Sendable, Equatable {
    case missingKey
    case alreadyReserved(String)
}

/// At-most-once reservation facade backed by injected storage. Reservations
/// are never released after execution failure.
public actor IdempotencyStore {
    private let store: any IdempotencyStateStore

    public init(
        store: any IdempotencyStateStore = InMemoryApprovalStateStore()
    ) {
        self.store = store
    }

    public func reserve(_ key: String) async throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw IdempotencyError.missingKey
        }
        guard try await store.reserveIdempotencyKey(normalized) else {
            throw IdempotencyError.alreadyReserved(normalized)
        }
    }

    public func contains(_ key: String) async -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? await store.containsIdempotencyKey(normalized)) == true
    }
}
