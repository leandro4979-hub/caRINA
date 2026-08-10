import Foundation

public struct ApprovalChallenge: Sendable, Equatable {
    public let id: UUID
    public let fingerprint: String
    public let expiresAt: Date
    public let target: String
    public let correlationID: UUID

    fileprivate init(id: UUID = UUID(), envelope: CommandEnvelope, expiresAt: Date) {
        self.id = id
        self.fingerprint = ApprovalFingerprint.make(for: envelope)
        self.expiresAt = expiresAt
        self.target = envelope.request.target
        self.correlationID = envelope.requestID
    }
}

public struct AuthorizationToken: Sendable, Equatable {
    public let id: UUID
    public let fingerprint: String
    public let expiresAt: Date

    fileprivate init(id: UUID, fingerprint: String, expiresAt: Date) {
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

/// Owns both approval-challenge and authorization-token mutable state.
/// Challenge consumption and token issuance happen in the same actor turn,
/// so one human approval can mint at most one authorization token.
public actor ApprovalVerifier {
    private var challenges: [UUID: ApprovalChallenge] = [:]
    private var tokens: [UUID: AuthorizationToken] = [:]
    private let journal: ActionActivityJournal?

    public init(journal: ActionActivityJournal? = nil) {
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
        challenges[challenge.id] = challenge
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
        guard let stored = challenges[challenge.id], stored == challenge else {
            throw AuthorizationError.challengeUnknownOrConsumed
        }

        // Burn before returning or awaiting external work. A denial, expiry,
        // or successful approval is terminal for this challenge.
        challenges[challenge.id] = nil

        guard stored.expiresAt > now else {
            if let journal {
                try await journal.record(challenge: stored, status: .expired)
            }
            throw AuthorizationError.challengeExpired
        }

        guard approved else {
            if let journal {
                try await journal.record(challenge: stored, status: .denied)
            }
            return nil
        }

        let token = AuthorizationToken(
            id: UUID(),
            fingerprint: stored.fingerprint,
            expiresAt: stored.expiresAt
        )
        tokens[token.id] = token

        if let journal {
            try await journal.record(challenge: stored, status: .approved)
        }
        return token
    }

    /// Validates and burns an authorization token atomically. The token is
    /// consumed before privileged execution begins and is never resurrected.
    public func consume(
        _ presentedToken: AuthorizationToken,
        expectedFingerprint: String,
        now: Date = Date()
    ) throws {
        guard let storedToken = tokens[presentedToken.id],
              storedToken == presentedToken else {
            throw AuthorizationError.tokenUnknownOrConsumed
        }

        tokens[presentedToken.id] = nil

        guard storedToken.expiresAt > now else {
            throw AuthorizationError.tokenExpired
        }
        guard storedToken.fingerprint == expectedFingerprint else {
            throw AuthorizationError.fingerprintMismatch
        }
    }
}
