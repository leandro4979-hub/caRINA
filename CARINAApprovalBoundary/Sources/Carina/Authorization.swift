import Foundation

public struct ApprovalChallenge: Sendable, Equatable {
    public let id: UUID
    public let fingerprint: String
    public let expiresAt: Date
    public let target: String
    public let correlationID: UUID

    init(id: UUID = UUID(), envelope: CommandEnvelope, expiresAt: Date) {
        self.init(
            id: id,
            fingerprint: ApprovalFingerprint.make(for: envelope),
            expiresAt: expiresAt,
            target: envelope.request.target,
            correlationID: envelope.requestID
        )
    }

    init(
        id: UUID,
        fingerprint: String,
        expiresAt: Date,
        target: String,
        correlationID: UUID
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.expiresAt = expiresAt
        self.target = target
        self.correlationID = correlationID
    }
}

public struct AuthorizationToken: Sendable, Equatable {
    public let id: UUID
    public let fingerprint: String
    public let expiresAt: Date

    init(id: UUID, fingerprint: String, expiresAt: Date) {
        self.id = id
        self.fingerprint = fingerprint
        self.expiresAt = expiresAt
    }
}

public enum AuthorizationError: Error, Sendable, Equatable {
    case challengeExpired
    case challengeUnknownOrConsumed
    case tokenExpired
    case tokenUnknownOrConsumed
    case fingerprintMismatch
}

/// Coordinates approval against an injected state store. Production uses
/// SQLiteApprovalStateStore so challenges and tokens survive process restarts.
public actor ApprovalVerifier {
    private let store: any AuthorizationStateStore
    private let journal: ActionActivityJournal?

    public init(
        store: any AuthorizationStateStore = InMemoryApprovalStateStore(),
        journal: ActionActivityJournal? = nil
    ) {
        self.store = store
        self.journal = journal
    }

    public func createChallenge(
        envelope: CommandEnvelope,
        expiresAt: Date
    ) async throws -> ApprovalChallenge {
        let challenge = ApprovalChallenge(
            envelope: envelope,
            expiresAt: expiresAt
        )
        try await store.insertChallenge(challenge)
        if let journal {
            try await journal.record(challenge: challenge, status: .prepared)
        }
        return challenge
    }

    public func authorize(
        challenge: ApprovalChallenge,
        approved: Bool,
        now: Date = Date()
    ) async throws -> AuthorizationToken? {
        let isExpired = challenge.expiresAt <= now
        let token: AuthorizationToken? = approved && !isExpired
            ? AuthorizationToken(
                id: UUID(),
                fingerprint: challenge.fingerprint,
                expiresAt: challenge.expiresAt
            )
            : nil

        guard try await store.resolveChallenge(challenge, issuing: token) else {
            throw AuthorizationError.challengeUnknownOrConsumed
        }

        if isExpired {
            if let journal {
                try await journal.record(challenge: challenge, status: .expired)
            }
            throw AuthorizationError.challengeExpired
        }

        guard approved else {
            if let journal {
                try await journal.record(challenge: challenge, status: .denied)
            }
            return nil
        }

        if let journal {
            try await journal.record(challenge: challenge, status: .approved)
        }
        return token
    }

    /// Atomically loads and deletes the token before validating its expiry and
    /// fingerprint. Any presentation attempt permanently burns the capability.
    public func consume(
        _ presentedToken: AuthorizationToken,
        expectedFingerprint: String,
        now: Date = Date()
    ) async throws {
        guard let storedToken = try await store.consumeToken(presentedToken),
              storedToken == presentedToken else {
            throw AuthorizationError.tokenUnknownOrConsumed
        }

        guard storedToken.expiresAt > now else {
            throw AuthorizationError.tokenExpired
        }
        guard storedToken.fingerprint == expectedFingerprint else {
            throw AuthorizationError.fingerprintMismatch
        }
    }
}
