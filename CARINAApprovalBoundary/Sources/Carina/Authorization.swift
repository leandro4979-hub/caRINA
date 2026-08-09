import Foundation

public struct ApprovalChallenge: Sendable, Equatable {
    public let id: UUID
    public let fingerprint: String
    public let expiresAt: Date
    public let target: String
    public let correlationID: UUID

    public init(id: UUID = UUID(), envelope: CommandEnvelope, expiresAt: Date) {
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
    case tokenExpired
    case tokenUnknownOrConsumed
    case fingerprintMismatch
}

/// The authority that owns token state. Validation and deletion happen in one
/// actor turn, making successful consumption exactly once within this process.
public actor AuthorizationTokenVault {
    private var tokens: [UUID: AuthorizationToken] = [:]

    public init() {}

    fileprivate func issue(
        fingerprint: String,
        expiresAt: Date,
        id: UUID = UUID()
    ) -> AuthorizationToken {
        let token = AuthorizationToken(
            id: id,
            fingerprint: fingerprint,
            expiresAt: expiresAt
        )
        tokens[id] = token
        return token
    }

    public func consume(
        _ presentedToken: AuthorizationToken,
        expectedFingerprint: String,
        now: Date = Date()
    ) throws {
        guard let storedToken = tokens[presentedToken.id],
              storedToken == presentedToken else {
            throw AuthorizationError.tokenUnknownOrConsumed
        }

        // Delete before any result is returned. Expired and mismatched tokens
        // are terminal too, preventing probing or retry with altered input.
        tokens[presentedToken.id] = nil

        guard storedToken.expiresAt > now else {
            throw AuthorizationError.tokenExpired
        }
        guard storedToken.fingerprint == expectedFingerprint else {
            throw AuthorizationError.fingerprintMismatch
        }
    }
}

public struct ApprovalVerifier: Sendable {
    private let vault: AuthorizationTokenVault
    private let journal: ActionActivityJournal?

    public init(vault: AuthorizationTokenVault, journal: ActionActivityJournal? = nil) {
        self.vault = vault
        self.journal = journal
    }

    public func authorize(
        challenge: ApprovalChallenge,
        approved: Bool,
        now: Date = Date()
    ) async throws -> AuthorizationToken? {
        guard approved else {
            if let journal { try await journal.record(challenge: challenge, status: .denied) }
            return nil
        }
        guard challenge.expiresAt > now else {
            if let journal { try await journal.record(challenge: challenge, status: .expired) }
            throw AuthorizationError.challengeExpired
        }
        let token = await vault.issue(
            fingerprint: challenge.fingerprint,
            expiresAt: challenge.expiresAt
        )
        if let journal { try await journal.record(challenge: challenge, status: .approved) }
        return token
    }
}
