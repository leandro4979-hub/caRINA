import Foundation

public struct ApprovalChallenge: Sendable, Equatable {
    public let id: UUID
    public let fingerprint: String
    public let expiresAt: Date

    public init(id: UUID = UUID(), envelope: CommandEnvelope, expiresAt: Date) {
        self.id = id
        self.fingerprint = ApprovalFingerprint.make(for: envelope)
        self.expiresAt = expiresAt
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

    public init(vault: AuthorizationTokenVault) {
        self.vault = vault
    }

    public func authorize(
        challenge: ApprovalChallenge,
        approved: Bool,
        now: Date = Date()
    ) async throws -> AuthorizationToken? {
        guard approved else { return nil }
        guard challenge.expiresAt > now else {
            throw AuthorizationError.challengeExpired
        }
        return await vault.issue(
            fingerprint: challenge.fingerprint,
            expiresAt: challenge.expiresAt
        )
    }
}
