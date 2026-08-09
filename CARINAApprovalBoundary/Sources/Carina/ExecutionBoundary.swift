import Foundation

public enum DispatchResult: Sendable, Equatable {
    case query
    case preparation
    case approvalRequired(ApprovalChallenge)
}

public enum CommandPermission: Sendable {
    case read
    case prepare
    case execute
}

/// Dispatch ends at an approval challenge. It deliberately has no reference
/// to ProtectedExecutionService or AppIntentAdapter.
public struct CommandDispatcher: Sendable {
    private let replayProtector: ReplayProtector
    private let approvalTTL: TimeInterval
    private let journal: ActionActivityJournal?

    public init(
        replayProtector: ReplayProtector,
        approvalTTL: TimeInterval = 60,
        journal: ActionActivityJournal? = nil
    ) {
        precondition(approvalTTL > 0)
        self.replayProtector = replayProtector
        self.approvalTTL = approvalTTL
        self.journal = journal
    }

    public func dispatch(
        envelope: CommandEnvelope,
        permission: CommandPermission,
        now: Date = Date()
    ) async throws -> DispatchResult {
        try await replayProtector.reserve(envelope, now: now)
        switch permission {
        case .read:
            return .query
        case .prepare:
            return .preparation
        case .execute:
            let challenge = ApprovalChallenge(envelope: envelope, expiresAt: now.addingTimeInterval(approvalTTL))
            if let journal { try await journal.record(challenge: challenge, status: .prepared) }
            return .approvalRequired(challenge)
        }
    }
}

public protocol AppIntentAdapter: Sendable {
    associatedtype Output: Sendable
    func execute(_ request: CommandRequest) async throws -> Output
}

public struct ProtectedExecutionService<Adapter: AppIntentAdapter>: Sendable {
    private let vault: AuthorizationTokenVault
    private let adapter: Adapter
    private let journal: ActionActivityJournal?

    public init(vault: AuthorizationTokenVault, adapter: Adapter, journal: ActionActivityJournal? = nil) {
        self.vault = vault
        self.adapter = adapter
        self.journal = journal
    }

    public func execute(
        envelope: CommandEnvelope,
        authorization: AuthorizationToken,
        now: Date = Date()
    ) async throws -> Adapter.Output {
        let currentFingerprint = ApprovalFingerprint.make(for: envelope)
        let challenge = ApprovalChallenge(envelope: envelope, expiresAt: authorization.expiresAt)
        do {
            try await vault.consume(authorization, expectedFingerprint: currentFingerprint, now: now)
        } catch {
            if let journal { try await journal.record(challenge: challenge, status: error as? AuthorizationError == .tokenExpired ? .expired : .failedBeforeExecution) }
            throw error
        }
        do {
            let output = try await adapter.execute(envelope.request)
            if let journal { try await journal.record(challenge: challenge, status: .executed) }
            return output
        } catch {
            if let journal { try await journal.record(challenge: challenge, status: .executedWithWarning) }
            throw error
        }
    }
}
