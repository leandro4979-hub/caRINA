import Foundation

public struct ReplayKey: Hashable, Sendable {
    public let sessionID: UUID
    public let sequence: UInt64
    public let nonce: UUID

    public init(sessionID: UUID, sequence: UInt64, nonce: UUID) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.nonce = nonce
    }

    public init(envelope: CommandEnvelope) {
        self.init(
            sessionID: envelope.sessionID,
            sequence: envelope.sequence,
            nonce: envelope.nonce
        )
    }
}

public enum ReplayProtectionError: Error, Sendable, Equatable {
    case replayDetected(ReplayKey)
}

/// Replay reservations are delegated to an injected atomic store. Production
/// uses SQLiteApprovalStateStore, preserving reservations across restarts.
public actor ReplayProtector {
    private let store: any ReplayStateStore
    private let retention: TimeInterval

    public init(
        store: any ReplayStateStore = InMemoryApprovalStateStore(),
        retention: TimeInterval = 24 * 60 * 60
    ) {
        precondition(retention > 0)
        self.store = store
        self.retention = retention
    }

    public func reserve(
        _ envelope: CommandEnvelope,
        now: Date = Date()
    ) async throws {
        let key = ReplayKey(envelope: envelope)
        let inserted = try await store.reserveReplay(
            key,
            expiresAt: now.addingTimeInterval(retention),
            now: now
        )
        guard inserted else {
            throw ReplayProtectionError.replayDetected(key)
        }
    }
}
