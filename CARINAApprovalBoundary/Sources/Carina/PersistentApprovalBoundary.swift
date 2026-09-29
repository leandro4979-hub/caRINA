import Foundation

public enum ProductionPolicyError: Error, Sendable, Equatable {
    case unknownCapability(CommandIntentID)
    case unknownInput(String)
    case recipientLimit
    case accountNotAllowed
    case missingIdempotencyKey
    case emptyTarget
}

/// Registry-derived routing. No request, model output, or view can select its
/// own permission: permission comes exclusively from the immutable snapshot.
public struct ProductionCommandRouter: Sendable {
    private let registry: CapabilityRegistrySnapshot
    private let dispatcher: CommandDispatcher
    private let capabilityVersionMajor: Int

    public init(
        registry: CapabilityRegistrySnapshot,
        dispatcher: CommandDispatcher,
        capabilityVersionMajor: Int = 1
    ) {
        self.registry = registry
        self.dispatcher = dispatcher
        self.capabilityVersionMajor = capabilityVersionMajor
    }

    public func route(
        envelope: CommandEnvelope,
        now: Date = Date()
    ) async throws -> DispatchResult {
        let permission = try permission(for: envelope.request)
        return try await dispatcher.dispatch(
            envelope: envelope,
            permission: permission,
            now: now
        )
    }

    public func permission(
        for request: CommandRequest
    ) throws -> CommandPermission {
        guard let capability = registry.capability(
            id: request.intentID.rawValue,
            versionMajor: capabilityVersionMajor
        ) else {
            throw ProductionPolicyError.unknownCapability(request.intentID)
        }

        guard !request.target.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw ProductionPolicyError.emptyTarget
        }

        for key in request.payload.keys
        where !capability.allowedInputs.contains(key) {
            throw ProductionPolicyError.unknownInput(key)
        }

        if let recipients = request.payload["recipients"],
           recipients.split(separator: ",").count > capability.maxRecipients {
            throw ProductionPolicyError.recipientLimit
        }

        if let account = request.payload["account"],
           !capability.allowedAccounts.isEmpty,
           !capability.allowedAccounts.contains(account) {
            throw ProductionPolicyError.accountNotAllowed
        }

        switch capability.kind {
        case .read:
            return .read
        case .draft, .stage:
            return .prepare
        case .commit, .admin:
            guard let key = request.payload["idempotencyKey"],
                  !key.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else {
                throw ProductionPolicyError.missingIdempotencyKey
            }
            return .execute
        }
    }
}

/// One composition root for the registry, dispatcher, verifier, durable state,
/// protected executor, and the reviewed platform adapter.
public struct PersistentApprovalBoundary<Adapter: AppIntentAdapter>: Sendable {
    public let store: SQLiteApprovalStateStore
    public let verifier: ApprovalVerifier
    public let router: ProductionCommandRouter
    public let executor: ProtectedExecutionService<Adapter>

    public init(
        databaseURL: URL,
        registry: CapabilityRegistrySnapshot,
        adapter: Adapter,
        journalURL: URL? = nil,
        approvalTTL: TimeInterval = 60,
        replayRetention: TimeInterval = 24 * 60 * 60
    ) throws {
        let store = try SQLiteApprovalStateStore(databaseURL: databaseURL)
        let journal = try ActionActivityJournal(fileURL: journalURL)
        let verifier = ApprovalVerifier(store: store, journal: journal)
        let replayProtector = ReplayProtector(
            store: store,
            retention: replayRetention
        )
        let dispatcher = CommandDispatcher(
            replayProtector: replayProtector,
            approvalVerifier: verifier,
            approvalTTL: approvalTTL
        )
        let idempotencyStore = IdempotencyStore(store: store)

        self.store = store
        self.verifier = verifier
        self.router = ProductionCommandRouter(
            registry: registry,
            dispatcher: dispatcher
        )
        self.executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: idempotencyStore,
            adapter: adapter,
            journal: journal
        )
    }

    public func prepare(
        envelope: CommandEnvelope,
        now: Date = Date()
    ) async throws -> DispatchResult {
        try await router.route(envelope: envelope, now: now)
    }

    public func authorize(
        challenge: ApprovalChallenge,
        approved: Bool,
        now: Date = Date()
    ) async throws -> AuthorizationToken? {
        try await verifier.authorize(
            challenge: challenge,
            approved: approved,
            now: now
        )
    }

    public func execute(
        envelope: CommandEnvelope,
        authorization: AuthorizationToken,
        now: Date = Date()
    ) async throws -> Adapter.Output {
        try await executor.execute(
            envelope: envelope,
            authorization: authorization,
            now: now
        )
    }
}
