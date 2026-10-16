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
    public let workerID: String
    public let role: AgentWorkerRole
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
        workerID: String,
        role: AgentWorkerRole,
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
        self.workerID = workerID
        self.role = role
        self.claim = claim
        self.evidencePointers = evidencePointers
        self.inspected = inspected
        self.notInspected = notInspected
        self.contradictions = contradictions
        self.requiresReproduction = requiresReproduction
        self.submittedAt = submittedAt
    }
}

public struct AgentWorkItem: Codable, Sendable, Equatable {
    public let taskID: UUID
    public let scopeHash: String
    public let stage: AgentWorkStage
    public let reports: [AgentEvidenceReport]

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
        reports: [AgentEvidenceReport]
    ) {
        self.taskID = taskID
        self.scopeHash = scopeHash
        self.stage = stage
        self.reports = reports
    }

    fileprivate func appending(
        _ report: AgentEvidenceReport,
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
    case emptyWorkerID
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
    public init() {}

    public func submit(
        _ report: AgentEvidenceReport,
        outcome: AgentSubmissionOutcome,
        for item: AgentWorkItem
    ) throws -> AgentWorkItem {
        try validateIdentity(report, item: item)
        try validateEvidence(report)

        guard item.stage != .verified, item.stage != .blocked else {
            throw AgentWorkError.terminalStage(item.stage)
        }

        let expectedRole = roleRequired(for: item.stage)
        guard report.role == expectedRole else {
            throw AgentWorkError.wrongRole(
                expected: expectedRole,
                actual: report.role
            )
        }

        guard !item.reports.contains(where: { $0.workerID == report.workerID }) else {
            throw AgentWorkError.workerSeparationViolation(report.workerID)
        }

        if outcome == .block {
            return item.appending(report, stage: .blocked)
        }

        guard report.contradictions.isEmpty else {
            throw AgentWorkError.unresolvedContradictions
        }
        guard !report.requiresReproduction else {
            throw AgentWorkError.reproductionRequired
        }

        return item.appending(report, stage: nextStage(after: item.stage))
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
        guard !report.workerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentWorkError.emptyWorkerID
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
