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

    public init(
        replayProtector: ReplayProtector,
        approvalTTL: TimeInterval = 60
    ) {
        precondition(approvalTTL > 0)
        self.replayProtector = replayProtector
        self.approvalTTL = approvalTTL
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
            return .approvalRequired(
                ApprovalChallenge(
                    envelope: envelope,
                    expiresAt: now.addingTimeInterval(approvalTTL)
                )
            )
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

    public init(vault: AuthorizationTokenVault, adapter: Adapter) {
        self.vault = vault
        self.adapter = adapter
    }

    public func execute(
        envelope: CommandEnvelope,
        authorization: AuthorizationToken,
        now: Date = Date()
    ) async throws -> Adapter.Output {
        let currentFingerprint = ApprovalFingerprint.make(for: envelope)
        try await vault.consume(
            authorization,
            expectedFingerprint: currentFingerprint,
            now: now
        )
        return try await adapter.execute(envelope.request)
    }
}
