import CryptoKit
import Foundation

public enum FileOperation: String, Codable, Sendable, Hashable {
    case create
    case modify
    case delete
    case rename
}

public enum ProtectionTier: String, Codable, Sendable, Comparable {
    case frictionless
    case biometric
    case biometricAndApproval

    private var rank: Int {
        switch self {
        case .frictionless: return 0
        case .biometric: return 1
        case .biometricAndApproval: return 2
        }
    }

    public static func < (lhs: ProtectionTier, rhs: ProtectionTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct ProposedFileMutation: Codable, Sendable, Equatable {
    public let oldPath: String?
    public let newPath: String?
    public let operation: FileOperation

    public init(oldPath: String?, newPath: String?, operation: FileOperation) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.operation = operation
    }
}

public struct EngineeringProposal: Codable, Sendable {
    public let proposalID: UUID
    public let sourceToolID: String
    public let sourceContractVersion: UInt64
    public let repoRoot: String
    public let affectedFiles: [ProposedFileMutation]
    public let summary: String
    public let rationale: String
    public let proposedDiff: String?
    public let testPlan: [String]
    public let risks: [String]
    public let createdAt: Date
    public let expiresAt: Date

    public init(
        proposalID: UUID,
        sourceToolID: String,
        sourceContractVersion: UInt64,
        repoRoot: String,
        affectedFiles: [ProposedFileMutation],
        summary: String,
        rationale: String,
        proposedDiff: String?,
        testPlan: [String],
        risks: [String],
        createdAt: Date,
        expiresAt: Date
    ) {
        self.proposalID = proposalID
        self.sourceToolID = sourceToolID
        self.sourceContractVersion = sourceContractVersion
        self.repoRoot = repoRoot
        self.affectedFiles = affectedFiles
        self.summary = summary
        self.rationale = rationale
        self.proposedDiff = proposedDiff
        self.testPlan = testPlan
        self.risks = risks
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct ValidatedFileMutation: Codable, Sendable, Equatable {
    public let oldCanonicalPath: String?
    public let newCanonicalPath: String?
    public let operation: FileOperation
    public let destructive: Bool
}

public struct ValidatedEngineeringProposal: Codable, Sendable {
    public let proposalID: UUID
    public let validationID: UUID
    public let sourceToolID: String
    public let sourceContractVersion: UInt64
    public let registryVersion: UInt64
    public let repoRoot: String
    public let affectedFiles: [ValidatedFileMutation]
    public let summary: String
    public let rationale: String
    public let proposedDiff: String?
    public let testPlan: [String]
    public let risks: [String]
    public let canonicalPayloadDigest: String
    public let policyTier: ProtectionTier
    public let validatedAt: Date
    public let expiresAt: Date
}

public struct ToolContract: Sendable {
    public let toolID: String
    public let version: UInt64

    public init(toolID: String, version: UInt64) {
        self.toolID = toolID
        self.version = version
    }
}

public struct RepositoryPolicy: Sendable {
    public let canonicalRoot: String
    public let createTier: ProtectionTier
    public let modifyTier: ProtectionTier
    public let deleteTier: ProtectionTier
    public let renameTier: ProtectionTier

    public init(
        canonicalRoot: String,
        createTier: ProtectionTier,
        modifyTier: ProtectionTier,
        deleteTier: ProtectionTier,
        renameTier: ProtectionTier
    ) {
        self.canonicalRoot = canonicalRoot
        self.createTier = createTier
        self.modifyTier = modifyTier
        self.deleteTier = deleteTier
        self.renameTier = renameTier
    }
}

public struct RegistrySnapshot: Sendable {
    public let version: UInt64
    public let tools: [String: ToolContract]
    public let repositories: [String: RepositoryPolicy]

    public init(version: UInt64, tools: [String: ToolContract], repositories: [String: RepositoryPolicy]) {
        self.version = version
        self.tools = tools
        self.repositories = repositories
    }
}

public protocol CanonicalPathResolving: Sendable {
    func canonicalize(path: String, relativeTo root: String) throws -> String
    func canonicalizeRoot(_ path: String) throws -> String
    func isContained(path: String, inside root: String) -> Bool
}

public protocol ProposalReplayChecking: Sendable {
    func contains(proposalID: UUID) throws -> Bool
    func containsDigest(_ digest: String) throws -> Bool
}

public enum ProposalValidationError: Error, Equatable, Sendable {
    case invalidSchema
    case unknownSourceTool(String)
    case contractVersionMismatch(expected: UInt64, received: UInt64)
    case repoOutsideRegistry(String)
    case pathOutsideScope(path: String)
    case conflictingOperations(path: String)
    case missingDiffForDeclaredMutations
    case mutationMismatch(path: String, declared: FileOperation?, observed: FileOperation?)
    case malformedRename
    case duplicateMutation(path: String)
    case staleProposal
    case expiredProposal
    case replayedProposal
    case replayedDigest
    case canonicalizationFailure(String)
}

public struct StandardCanonicalPathResolver: CanonicalPathResolving {
    public init() {}

    public func canonicalizeRoot(_ path: String) throws -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    public func canonicalize(path: String, relativeTo root: String) throws -> String {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(path)
        }
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    public func isContained(path: String, inside root: String) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let rootComponents = URL(fileURLWithPath: root).standardizedFileURL.pathComponents
        guard pathComponents.count >= rootComponents.count else { return false }
        return Array(pathComponents.prefix(rootComponents.count)) == rootComponents
    }
}

public struct ProposalValidator: Sendable {
    private let diffInspector: DiffMutationInspector
    private let registry: RegistrySnapshot
    private let pathResolver: any CanonicalPathResolving
    private let replayStore: any ProposalReplayChecking
    private let maximumValidationLifetime: TimeInterval

    public init(
        diffInspector: DiffMutationInspector = DiffMutationInspector(),
        registry: RegistrySnapshot,
        pathResolver: any CanonicalPathResolving,
        replayStore: any ProposalReplayChecking,
        maximumValidationLifetime: TimeInterval = 300
    ) {
        self.diffInspector = diffInspector
        self.registry = registry
        self.pathResolver = pathResolver
        self.replayStore = replayStore
        self.maximumValidationLifetime = maximumValidationLifetime
    }

    public func validate(_ proposal: EngineeringProposal, now: Date = Date()) throws -> ValidatedEngineeringProposal {
        guard proposal.createdAt <= now else { throw ProposalValidationError.staleProposal }
        guard proposal.expiresAt > now else { throw ProposalValidationError.expiredProposal }

        guard let tool = registry.tools[proposal.sourceToolID] else {
            throw ProposalValidationError.unknownSourceTool(proposal.sourceToolID)
        }
        guard tool.version == proposal.sourceContractVersion else {
            throw ProposalValidationError.contractVersionMismatch(expected: tool.version, received: proposal.sourceContractVersion)
        }

        let canonicalRepoRoot: String
        do {
            canonicalRepoRoot = try pathResolver.canonicalizeRoot(proposal.repoRoot)
        } catch {
            throw ProposalValidationError.canonicalizationFailure(proposal.repoRoot)
        }

        guard let repositoryPolicy = registry.repositories[canonicalRepoRoot] else {
            throw ProposalValidationError.repoOutsideRegistry(canonicalRepoRoot)
        }

        let declared = try canonicalizeDeclared(proposal.affectedFiles, repoRoot: canonicalRepoRoot)
        try rejectPathCollisions(declared)

        if !declared.isEmpty && proposal.proposedDiff == nil {
            throw ProposalValidationError.missingDiffForDeclaredMutations
        }

        let observed: [CanonicalMutation]
        if let diff = proposal.proposedDiff {
            let parsed = try diffInspector.inspect(diff)
            observed = try canonicalizeObserved(parsed, repoRoot: canonicalRepoRoot)
        } else {
            observed = []
        }

        try rejectPathCollisions(observed)
        try reconcile(declared: declared, observed: observed)

        let policyTier = resolvePolicyTier(mutations: declared, repositoryPolicy: repositoryPolicy)
        let validatedFiles = declared.sorted(by: canonicalMutationSort).map {
            ValidatedFileMutation(
                oldCanonicalPath: $0.oldPath,
                newCanonicalPath: $0.newPath,
                operation: $0.operation,
                destructive: $0.operation == .delete || $0.operation == .rename
            )
        }

        let canonicalPayload = CanonicalProposalPayload(
            proposalID: proposal.proposalID,
            sourceToolID: proposal.sourceToolID,
            sourceContractVersion: proposal.sourceContractVersion,
            registryVersion: registry.version,
            repoRoot: canonicalRepoRoot,
            affectedFiles: validatedFiles,
            summary: proposal.summary,
            rationale: proposal.rationale,
            proposedDiff: proposal.proposedDiff,
            testPlan: proposal.testPlan,
            risks: proposal.risks
        )
        let digest = try canonicalDigest(canonicalPayload)

        if try replayStore.contains(proposalID: proposal.proposalID) {
            throw ProposalValidationError.replayedProposal
        }
        if try replayStore.containsDigest(digest) {
            throw ProposalValidationError.replayedDigest
        }

        return ValidatedEngineeringProposal(
            proposalID: proposal.proposalID,
            validationID: UUID(),
            sourceToolID: proposal.sourceToolID,
            sourceContractVersion: proposal.sourceContractVersion,
            registryVersion: registry.version,
            repoRoot: canonicalRepoRoot,
            affectedFiles: validatedFiles,
            summary: proposal.summary,
            rationale: proposal.rationale,
            proposedDiff: proposal.proposedDiff,
            testPlan: proposal.testPlan,
            risks: proposal.risks,
            canonicalPayloadDigest: digest,
            policyTier: policyTier,
            validatedAt: now,
            expiresAt: min(proposal.expiresAt, now.addingTimeInterval(maximumValidationLifetime))
        )
    }
}

private extension ProposalValidator {
    struct CanonicalMutation: Hashable, Sendable {
        let oldPath: String?
        let newPath: String?
        let operation: FileOperation

        var identity: MutationIdentity {
            operation == .rename
                ? .rename(from: oldPath ?? "", to: newPath ?? "")
                : .path(newPath ?? oldPath ?? "")
        }

        var displayPath: String { newPath ?? oldPath ?? "" }
    }

    enum MutationIdentity: Hashable {
        case path(String)
        case rename(from: String, to: String)
    }

    func canonicalizeDeclared(_ mutations: [ProposedFileMutation], repoRoot: String) throws -> [CanonicalMutation] {
        try mutations.map {
            try canonicalizeMutation(oldPath: $0.oldPath, newPath: $0.newPath, operation: $0.operation, repoRoot: repoRoot)
        }
    }

    func canonicalizeObserved(_ mutations: [ObservedMutation], repoRoot: String) throws -> [CanonicalMutation] {
        try mutations.map {
            try canonicalizeMutation(oldPath: $0.oldPath, newPath: $0.newPath, operation: $0.operation, repoRoot: repoRoot)
        }
    }

    func canonicalizeMutation(oldPath: String?, newPath: String?, operation: FileOperation, repoRoot: String) throws -> CanonicalMutation {
        switch operation {
        case .create:
            guard oldPath == nil, let newPath else { throw ProposalValidationError.invalidSchema }
            return CanonicalMutation(oldPath: nil, newPath: try canonicalizeAndCheck(newPath, repoRoot: repoRoot), operation: .create)

        case .modify:
            guard let oldPath, let newPath else { throw ProposalValidationError.invalidSchema }
            let oldCanonical = try canonicalizeAndCheck(oldPath, repoRoot: repoRoot)
            let newCanonical = try canonicalizeAndCheck(newPath, repoRoot: repoRoot)
            guard oldCanonical == newCanonical else { throw ProposalValidationError.malformedRename }
            return CanonicalMutation(oldPath: oldCanonical, newPath: newCanonical, operation: .modify)

        case .delete:
            guard let oldPath, newPath == nil else { throw ProposalValidationError.invalidSchema }
            return CanonicalMutation(oldPath: try canonicalizeAndCheck(oldPath, repoRoot: repoRoot), newPath: nil, operation: .delete)

        case .rename:
            guard let oldPath, let newPath else { throw ProposalValidationError.malformedRename }
            let oldCanonical = try canonicalizeAndCheck(oldPath, repoRoot: repoRoot)
            let newCanonical = try canonicalizeAndCheck(newPath, repoRoot: repoRoot)
            guard oldCanonical != newCanonical else { throw ProposalValidationError.malformedRename }
            return CanonicalMutation(oldPath: oldCanonical, newPath: newCanonical, operation: .rename)
        }
    }

    func canonicalizeAndCheck(_ path: String, repoRoot: String) throws -> String {
        let canonical: String
        do {
            canonical = try pathResolver.canonicalize(path: path, relativeTo: repoRoot)
        } catch {
            throw ProposalValidationError.canonicalizationFailure(path)
        }
        guard pathResolver.isContained(path: canonical, inside: repoRoot) else {
            throw ProposalValidationError.pathOutsideScope(path: canonical)
        }
        return canonical
    }

    func rejectPathCollisions(_ mutations: [CanonicalMutation]) throws {
        var owners: [String: CanonicalMutation] = [:]
        for mutation in mutations {
            let touched = Set([mutation.oldPath, mutation.newPath].compactMap { $0 })
            for path in touched {
                if let existing = owners[path] {
                    if existing == mutation { throw ProposalValidationError.duplicateMutation(path: path) }
                    throw ProposalValidationError.conflictingOperations(path: path)
                }
                owners[path] = mutation
            }
        }
    }

    func reconcile(declared: [CanonicalMutation], observed: [CanonicalMutation]) throws {
        let declaredMap = try mutationMap(declared)
        let observedMap = try mutationMap(observed)
        let identities = Set(declaredMap.keys).union(observedMap.keys)

        for identity in identities {
            let declaredMutation = declaredMap[identity]
            let observedMutation = observedMap[identity]
            guard let declaredMutation, let observedMutation else {
                let path = declaredMutation?.displayPath ?? observedMutation?.displayPath ?? ""
                throw ProposalValidationError.mutationMismatch(path: path, declared: declaredMutation?.operation, observed: observedMutation?.operation)
            }
            guard declaredMutation == observedMutation else {
                throw ProposalValidationError.mutationMismatch(path: declaredMutation.displayPath, declared: declaredMutation.operation, observed: observedMutation.operation)
            }
        }
    }

    func mutationMap(_ mutations: [CanonicalMutation]) throws -> [MutationIdentity: CanonicalMutation] {
        var result: [MutationIdentity: CanonicalMutation] = [:]
        for mutation in mutations {
            if result[mutation.identity] != nil {
                throw ProposalValidationError.duplicateMutation(path: mutation.displayPath)
            }
            result[mutation.identity] = mutation
        }
        return result
    }

    func resolvePolicyTier(mutations: [CanonicalMutation], repositoryPolicy: RepositoryPolicy) -> ProtectionTier {
        mutations.reduce(.frictionless) { highest, mutation in
            let tier: ProtectionTier
            switch mutation.operation {
            case .create: tier = repositoryPolicy.createTier
            case .modify: tier = repositoryPolicy.modifyTier
            case .delete: tier = repositoryPolicy.deleteTier
            case .rename: tier = repositoryPolicy.renameTier
            }
            return max(highest, tier)
        }
    }

    func canonicalMutationSort(_ lhs: CanonicalMutation, _ rhs: CanonicalMutation) -> Bool {
        if lhs.displayPath != rhs.displayPath { return lhs.displayPath < rhs.displayPath }
        if lhs.operation.rawValue != rhs.operation.rawValue { return lhs.operation.rawValue < rhs.operation.rawValue }
        return (lhs.oldPath ?? "") < (rhs.oldPath ?? "")
    }
}

private struct CanonicalProposalPayload: Codable, Sendable {
    let proposalID: UUID
    let sourceToolID: String
    let sourceContractVersion: UInt64
    let registryVersion: UInt64
    let repoRoot: String
    let affectedFiles: [ValidatedFileMutation]
    let summary: String
    let rationale: String
    let proposedDiff: String?
    let testPlan: [String]
    let risks: [String]
}

private func canonicalDigest<T: Encodable>(_ payload: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(payload)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
