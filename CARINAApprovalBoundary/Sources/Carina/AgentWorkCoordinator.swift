import Foundation

public enum AgentWorkerRole: String, Codable, Sendable, Equatable {
    case scout
    case builder
    case securityReviewer
    case verifier
}

public enum AgentWorkStage: String, Codable, Sendable, Equatable {
    case queued
    case discovered
    case implementationProposed
    case securityReviewed
    case verified
    case blocked
}

public enum AgentSubmissionOutcome: String, Codable, Sendable, Equatable {
    case advance
    case block
}

/// Evidence returned by a worker. This structure can describe findings and
/// proposed work, but it deliberately cannot represent execution authority.
public struct AgentEvidenceReport: Codable, Sendable, Equatable {
    public let taskID: UUID
    public let scopeHash: String
    public let claim: String
    public let evidencePointers: [String]
    public let inspected: [String]
    public let notInspected: [String]
    public let contradictions: [String]
    public let requiresReproduction: Bool
    public let submittedAt: Date

    public init(
        taskID: UUID,
        scopeHash: String,
        claim: String,
        evidencePointers: [String],
        inspected: [String],
        notInspected: [String] = [],
        contradictions: [String] = [],
        requiresReproduction: Bool = false,
        submittedAt: Date = Date()
    ) {
        self.taskID = taskID
        self.scopeHash = scopeHash
        self.claim = claim
        self.evidencePointers = evidencePointers
        self.inspected = inspected
        self.notInspected = notInspected
        self.contradictions = contradictions
        self.requiresReproduction = requiresReproduction
        self.submittedAt = submittedAt
    }
}

/// An opaque, coordinator-instance-bound credential provisioned by trusted
/// setup code. A worker cannot construct a credential or change its binding.
public struct AgentWorkerCredential: Sendable, Equatable, Hashable {
    fileprivate let token: UUID

    fileprivate init(token: UUID) {
        self.token = token
    }
}

/// Evidence with provenance assigned by CARINA's trusted worker registry.
/// Workers cannot supply or change these identity fields in their report.
public struct AgentAcceptedReport: Sendable, Equatable {
    public let authenticatedWorkerID: String
    public let assignedRole: AgentWorkerRole
    public let outcome: AgentSubmissionOutcome
    public let fromStage: AgentWorkStage
    public let toStage: AgentWorkStage
    public let evidence: AgentEvidenceReport

    fileprivate init(
        authenticatedWorkerID: String,
        assignedRole: AgentWorkerRole,
        outcome: AgentSubmissionOutcome,
        fromStage: AgentWorkStage,
        toStage: AgentWorkStage,
        evidence: AgentEvidenceReport
    ) {
        self.authenticatedWorkerID = authenticatedWorkerID
        self.assignedRole = assignedRole
        self.outcome = outcome
        self.fromStage = fromStage
        self.toStage = toStage
        self.evidence = evidence
    }
}

/// Work items are intentionally not Decodable. Durable restoration is not
/// implemented by this in-memory reference boundary. A future trusted adapter
/// must authenticate and replay accepted transition events rather than trust a
/// serialized stage and report array.
public struct AgentWorkItem: Sendable, Equatable {
    public let taskID: UUID
    public let scopeHash: String
    public let stage: AgentWorkStage
    public let reports: [AgentAcceptedReport]

    public init(taskID: UUID = UUID(), scopeHash: String) {
        self.taskID = taskID
        self.scopeHash = scopeHash
        self.stage = .queued
        self.reports = []
    }

    private init(
        taskID: UUID,
        scopeHash: String,
        stage: AgentWorkStage,
        reports: [AgentAcceptedReport]
    ) {
        self.taskID = taskID
        self.scopeHash = scopeHash
        self.stage = stage
        self.reports = reports
    }

    fileprivate func appending(
        _ report: AgentAcceptedReport,
        stage: AgentWorkStage
    ) -> AgentWorkItem {
        AgentWorkItem(
            taskID: taskID,
            scopeHash: scopeHash,
            stage: stage,
            reports: reports + [report]
        )
    }
}

public enum AgentWorkError: Error, Sendable, Equatable {
    case terminalStage(AgentWorkStage)
    case taskMismatch
    case scopeMismatch
    case emptyWorkerRegistry
    case invalidRegisteredWorkerID
    case unknownWorkerCredential
    case emptyClaim
    case missingEvidence
    case missingInspection
    case wrongRole(expected: AgentWorkerRole, actual: AgentWorkerRole)
    case workerSeparationViolation(String)
    case unresolvedContradictions
    case reproductionRequired
}

/// Enforces a segregated agent workflow:
/// Scout -> Builder -> Security Reviewer -> Verifier.
///
/// Reaching `verified` means the submitted evidence passed this workflow. It
/// never means an action is authorized. Privileged execution must still pass
/// CARINA's capability, approval, replay, and idempotency boundaries.
public struct AgentWorkCoordinator: Sendable {
    private struct WorkerBinding: Sendable {
        let authenticatedWorkerID: String
        let assignedRole: AgentWorkerRole
    }

    private let workerBindings: [UUID: WorkerBinding]

    private init(workerBindings: [UUID: WorkerBinding]) {
        self.workerBindings = workerBindings
    }

    /// Trusted setup maps canonical transport principals to roles and receives
    /// opaque credentials to distribute through the authenticated session. A
    /// credential created for another coordinator instance is rejected.
    public static func configure(
        workerRoles: [String: AgentWorkerRole]
    ) throws -> AgentWorkCoordinatorConfiguration {
        guard !workerRoles.isEmpty else {
            throw AgentWorkError.emptyWorkerRegistry
        }
        guard workerRoles.keys.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw AgentWorkError.invalidRegisteredWorkerID
        }

        var bindings: [UUID: WorkerBinding] = [:]
        var credentials: [String: AgentWorkerCredential] = [:]
        for (workerID, role) in workerRoles {
            let token = UUID()
            bindings[token] = WorkerBinding(
                authenticatedWorkerID: workerID,
                assignedRole: role
            )
            credentials[workerID] = AgentWorkerCredential(token: token)
        }

        return AgentWorkCoordinatorConfiguration(
            coordinator: AgentWorkCoordinator(workerBindings: bindings),
            credentials: credentials
        )
    }

    public func submit(
        _ report: AgentEvidenceReport,
        credential: AgentWorkerCredential,
        outcome: AgentSubmissionOutcome,
        for item: AgentWorkItem
    ) throws -> AgentWorkItem {
        try validateIdentity(report, item: item)
        try validateEvidence(report)

        guard item.stage != .verified, item.stage != .blocked else {
            throw AgentWorkError.terminalStage(item.stage)
        }

        guard let binding = workerBindings[credential.token] else {
            throw AgentWorkError.unknownWorkerCredential
        }

        let expectedRole = roleRequired(for: item.stage)
        guard binding.assignedRole == expectedRole else {
            throw AgentWorkError.wrongRole(
                expected: expectedRole,
                actual: binding.assignedRole
            )
        }

        guard !item.reports.contains(where: {
            $0.authenticatedWorkerID == binding.authenticatedWorkerID
        }) else {
            throw AgentWorkError.workerSeparationViolation(
                binding.authenticatedWorkerID
            )
        }

        let destination: AgentWorkStage
        if outcome == .block {
            destination = .blocked
        } else {
            guard report.contradictions.isEmpty else {
                throw AgentWorkError.unresolvedContradictions
            }
            guard !report.requiresReproduction else {
                throw AgentWorkError.reproductionRequired
            }
            destination = nextStage(after: item.stage)
        }

        let accepted = AgentAcceptedReport(
            authenticatedWorkerID: binding.authenticatedWorkerID,
            assignedRole: binding.assignedRole,
            outcome: outcome,
            fromStage: item.stage,
            toStage: destination,
            evidence: report
        )

        return item.appending(accepted, stage: destination)
    }

    private func validateIdentity(
        _ report: AgentEvidenceReport,
        item: AgentWorkItem
    ) throws {
        guard report.taskID == item.taskID else {
            throw AgentWorkError.taskMismatch
        }
        guard report.scopeHash == item.scopeHash,
              !item.scopeHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentWorkError.scopeMismatch
        }
    }

    private func validateEvidence(_ report: AgentEvidenceReport) throws {
        guard !report.claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentWorkError.emptyClaim
        }
        guard !report.evidencePointers.isEmpty,
              report.evidencePointers.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw AgentWorkError.missingEvidence
        }
        guard !report.inspected.isEmpty,
              report.inspected.allSatisfy({
                  !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw AgentWorkError.missingInspection
        }
    }

    private func roleRequired(for stage: AgentWorkStage) -> AgentWorkerRole {
        switch stage {
        case .queued:
            return .scout
        case .discovered:
            return .builder
        case .implementationProposed:
            return .securityReviewer
        case .securityReviewed:
            return .verifier
        case .verified, .blocked:
            preconditionFailure("Terminal stages are rejected before role lookup")
        }
    }

    private func nextStage(after stage: AgentWorkStage) -> AgentWorkStage {
        switch stage {
        case .queued:
            return .discovered
        case .discovered:
            return .implementationProposed
        case .implementationProposed:
            return .securityReviewed
        case .securityReviewed:
            return .verified
        case .verified, .blocked:
            preconditionFailure("Terminal stages cannot advance")
        }
    }
}

/// Provisioning result retained by trusted composition code. Workers receive
/// only their own opaque credential, never this complete credential set.
public struct AgentWorkCoordinatorConfiguration: Sendable {
    public let coordinator: AgentWorkCoordinator
    public let credentials: [String: AgentWorkerCredential]

    fileprivate init(
        coordinator: AgentWorkCoordinator,
        credentials: [String: AgentWorkerCredential]
    ) {
        self.coordinator = coordinator
        self.credentials = credentials
    }
}
