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

/// An in-memory implementation. Replace the storage with a transactional,
/// shared store when multiple CARINA processes accept commands.
public actor ReplayProtector {
    private var reservations: [ReplayKey: Date] = [:]
    private let retention: TimeInterval

    public init(retention: TimeInterval = 24 * 60 * 60) {
        precondition(retention > 0)
        self.retention = retention
    }

    public func reserve(
        _ envelope: CommandEnvelope,
        now: Date = Date()
    ) throws {
        prune(now: now)
        let key = ReplayKey(envelope: envelope)
        guard reservations[key] == nil else {
            throw ReplayProtectionError.replayDetected(key)
        }
        reservations[key] = now.addingTimeInterval(retention)
    }

    private func prune(now: Date) {
        reservations = reservations.filter { $0.value > now }
    }
}
