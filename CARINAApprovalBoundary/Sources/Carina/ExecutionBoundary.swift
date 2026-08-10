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

/// Dispatch validates replay first and can create an approval challenge, but
/// it deliberately has no path to privileged execution.
public struct CommandDispatcher: Sendable {
    private let replayProtector: ReplayProtector
    private let approvalVerifier: ApprovalVerifier
    private let approvalTTL: TimeInterval

    public init(
        replayProtector: ReplayProtector,
        approvalVerifier: ApprovalVerifier,
        approvalTTL: TimeInterval = 60
    ) {
        precondition(approvalTTL > 0)
        self.replayProtector = replayProtector
        self.approvalVerifier = approvalVerifier
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
            let challenge = try await approvalVerifier.createChallenge(
                envelope: envelope,
                expiresAt: now.addingTimeInterval(approvalTTL)
            )
            return .approvalRequired(challenge)
        }
    }
}

public protocol AppIntentAdapter: Sendable {
    associatedtype Output: Sendable
    func execute(_ request: CommandRequest) async throws -> Output
}

public enum ProtectedExecutionError: Error, Sendable, Equatable {
    case missingIdempotencyKey
}

/// Enforces the protected execution order:
/// consume token -> reserve idempotency key -> audit started -> invoke adapter
/// -> audit succeeded/failed. A failure after reservation intentionally burns
/// the operation. This is at-most-once invocation, not exactly-once completion.
public struct ProtectedExecutionService<Adapter: AppIntentAdapter>: Sendable {
    private let approvalVerifier: ApprovalVerifier
    private let idempotencyStore: IdempotencyStore
    private let adapter: Adapter
    private let journal: ActionActivityJournal?

    public init(
        approvalVerifier: ApprovalVerifier,
        idempotencyStore: IdempotencyStore,
        adapter: Adapter,
        journal: ActionActivityJournal? = nil
    ) {
        self.approvalVerifier = approvalVerifier
        self.idempotencyStore = idempotencyStore
        self.adapter = adapter
        self.journal = journal
    }

    public func execute(
        envelope: CommandEnvelope,
        authorization: AuthorizationToken,
        now: Date = Date()
    ) async throws -> Adapter.Output {
        let currentFingerprint = ApprovalFingerprint.make(for: envelope)

        do {
            try await approvalVerifier.consume(
                authorization,
                expectedFingerprint: currentFingerprint,
                now: now
            )
        } catch {
            if let journal {
                try await journal.record(
                    envelope: envelope,
                    status: error as? AuthorizationError == .tokenExpired
                        ? .expired
                        : .failedBeforeExecution,
                    now: now
                )
            }
            throw error
        }

        guard let idempotencyKey = envelope.request.payload["idempotencyKey"],
              !idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let journal {
                try await journal.record(
                    envelope: envelope,
                    status: .failedBeforeExecution,
                    now: now
                )
            }
            throw ProtectedExecutionError.missingIdempotencyKey
        }

        do {
            try await idempotencyStore.reserve(idempotencyKey)
        } catch {
            if let journal {
                try await journal.record(
                    envelope: envelope,
                    status: .failedBeforeExecution,
                    now: now
                )
            }
            throw error
        }

        if let journal {
            try await journal.record(
                envelope: envelope,
                status: .executionStarted,
                now: now
            )
        }

        do {
            let output = try await adapter.execute(envelope.request)
            if let journal {
                try await journal.record(
                    envelope: envelope,
                    status: .executionSucceeded,
                    now: now
                )
            }
            return output
        } catch {
            if let journal {
                try await journal.record(
                    envelope: envelope,
                    status: .executionFailed,
                    now: now
                )
            }
            throw error
        }
    }
}
