import Foundation
import XCTest
@testable import Carina

final class ProposalValidatorTests: XCTestCase {
    private let repoRoot = "/Users/leandro/Documents/CARINA"
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testRejectsParentTraversalOutsideRepo() throws {
        let validator = makeValidator()
        let proposal = makeProposal(
            mutations: [ProposedFileMutation(oldPath: "../Secrets/key.txt", newPath: "../Secrets/key.txt", operation: .modify)],
            diff: """
            diff --git a/../Secrets/key.txt b/../Secrets/key.txt
            --- a/../Secrets/key.txt
            +++ b/../Secrets/key.txt
            """
        )

        XCTAssertThrowsError(try validator.validate(proposal, now: now)) {
            XCTAssertEqual(
                $0 as? ProposalValidationError,
                .pathOutsideScope(path: "/Users/leandro/Documents/Secrets/key.txt")
            )
        }
    }

    func testRejectsPrefixCollisionPath() throws {
        let validator = makeValidator()
        let path = "/Users/leandro/Documents/CARINA-old/file.swift"
        let proposal = makeProposal(
            mutations: [ProposedFileMutation(oldPath: path, newPath: path, operation: .modify)],
            diff: """
            diff --git a/Sources/Config.swift b/Sources/Config.swift
            --- a/Sources/Config.swift
            +++ b/Sources/Config.swift
            """
        )

        XCTAssertThrowsError(try validator.validate(proposal, now: now)) {
            XCTAssertEqual($0 as? ProposalValidationError, .pathOutsideScope(path: path))
        }
    }

    func testAcceptsNormalizedPathInsideRepo() throws {
        let validator = makeValidator()
        let proposal = makeProposal(
            mutations: [ProposedFileMutation(oldPath: "Sources/../Tests/ValidatorTests.swift", newPath: "Sources/../Tests/ValidatorTests.swift", operation: .modify)],
            diff: """
            diff --git a/Sources/../Tests/ValidatorTests.swift b/Sources/../Tests/ValidatorTests.swift
            --- a/Sources/../Tests/ValidatorTests.swift
            +++ b/Sources/../Tests/ValidatorTests.swift
            """
        )

        XCTAssertNoThrow(try validator.validate(proposal, now: now))
    }

    func testRejectsMetadataModifyWhenDiffDeletesFile() throws {
        let validator = makeValidator()
        let proposal = makeProposal(
            mutations: [ProposedFileMutation(oldPath: "Sources/Config.swift", newPath: "Sources/Config.swift", operation: .modify)],
            diff: """
            diff --git a/Sources/Config.swift b/Sources/Config.swift
            deleted file mode 100644
            --- a/Sources/Config.swift
            +++ /dev/null
            """
        )

        XCTAssertThrowsError(try validator.validate(proposal, now: now)) {
            XCTAssertEqual(
                $0 as? ProposalValidationError,
                .mutationMismatch(
                    path: "\(repoRoot)/Sources/Config.swift",
                    declared: .modify,
                    observed: .delete
                )
            )
        }
    }

    func testRejectsHiddenDeletionOmittedFromMetadata() throws {
        let validator = makeValidator()
        let proposal = makeProposal(
            mutations: [],
            diff: """
            diff --git a/Sources/Unused.swift b/Sources/Unused.swift
            deleted file mode 100644
            --- a/Sources/Unused.swift
            +++ /dev/null
            """
        )

        XCTAssertThrowsError(try validator.validate(proposal, now: now)) {
            XCTAssertEqual(
                $0 as? ProposalValidationError,
                .mutationMismatch(
                    path: "\(repoRoot)/Sources/Unused.swift",
                    declared: nil,
                    observed: .delete
                )
            )
        }
    }

    func testRejectsConflictingOperationsForSameCanonicalPath() throws {
        let validator = makeValidator()
        let proposal = makeProposal(
            mutations: [
                ProposedFileMutation(oldPath: "Sources/Target.swift", newPath: "Sources/Target.swift", operation: .modify),
                ProposedFileMutation(oldPath: "Sources/Target.swift", newPath: nil, operation: .delete)
            ],
            diff: nil
        )

        XCTAssertThrowsError(try validator.validate(proposal, now: now)) {
            XCTAssertEqual(
                $0 as? ProposalValidationError,
                .conflictingOperations(path: "\(repoRoot)/Sources/Target.swift")
            )
        }
    }

    func testHighestPolicyTierWins() throws {
        let validator = makeValidator()
        let proposal = makeProposal(
            mutations: [
                ProposedFileMutation(oldPath: "Sources/A.swift", newPath: "Sources/A.swift", operation: .modify),
                ProposedFileMutation(oldPath: "Sources/B.swift", newPath: nil, operation: .delete)
            ],
            diff: """
            diff --git a/Sources/A.swift b/Sources/A.swift
            --- a/Sources/A.swift
            +++ b/Sources/A.swift
            diff --git a/Sources/B.swift b/Sources/B.swift
            deleted file mode 100644
            --- a/Sources/B.swift
            +++ /dev/null
            """
        )

        let validated = try validator.validate(proposal, now: now)
        XCTAssertEqual(validated.policyTier, .biometricAndApproval)
        XCTAssertFalse(validated.canonicalPayloadDigest.isEmpty)
    }

    func testFingerprintBindsFilesystemState() throws {
        let proposal = makeProposal(mutations: [], diff: nil)
        let first = makeValidator(filesystemBindings: [
            FilesystemStateBinding(
                path: "\(repoRoot)/A.swift",
                role: .source,
                expectation: .existing,
                device: 1,
                inode: 10,
                contentSHA256: String(repeating: "a", count: 64),
                parentDevice: 1,
                parentInode: 2
            )
        ])
        let second = makeValidator(filesystemBindings: [
            FilesystemStateBinding(
                path: "\(repoRoot)/A.swift",
                role: .source,
                expectation: .existing,
                device: 1,
                inode: 11,
                contentSHA256: String(repeating: "a", count: 64),
                parentDevice: 1,
                parentInode: 2
            )
        ])

        let lhs = try first.validate(proposal, now: now)
        let rhs = try second.validate(proposal, now: now)
        XCTAssertNotEqual(lhs.canonicalPayloadDigest, rhs.canonicalPayloadDigest)
    }

    func testRejectsExpiredAndReplayedProposal() throws {
        let expired = makeProposal(
            expiresAt: now.addingTimeInterval(-1),
            mutations: [],
            diff: nil
        )
        XCTAssertThrowsError(try makeValidator().validate(expired, now: now)) {
            XCTAssertEqual($0 as? ProposalValidationError, .expiredProposal)
        }

        let replayed = makeProposal(mutations: [], diff: nil)
        XCTAssertThrowsError(
            try makeValidator(replayedProposalIDs: [replayed.proposalID]).validate(replayed, now: now)
        ) {
            XCTAssertEqual($0 as? ProposalValidationError, .replayedProposal)
        }
    }

    private func makeValidator(
        replayedProposalIDs: Set<UUID> = [],
        filesystemBindings: [FilesystemStateBinding] = []
    ) -> ProposalValidator {
        let tool = ToolContract(toolID: "engineering.antigravity", version: 1)
        let policy = RepositoryPolicy(
            canonicalRoot: repoRoot,
            createTier: .biometric,
            modifyTier: .frictionless,
            deleteTier: .biometricAndApproval,
            renameTier: .biometricAndApproval
        )

        return ProposalValidator(
            registry: RegistrySnapshot(
                version: 7,
                tools: [tool.toolID: tool],
                repositories: [repoRoot: policy]
            ),
            pathResolver: StandardCanonicalPathResolver(),
            replayStore: StubProposalReplayStore(proposalIDs: replayedProposalIDs),
            filesystemBinder: StubFilesystemStateBinder(bindings: filesystemBindings)
        )
    }

    private func makeProposal(
        proposalID: UUID = UUID(),
        expiresAt: Date? = nil,
        mutations: [ProposedFileMutation],
        diff: String?
    ) -> EngineeringProposal {
        EngineeringProposal(
            proposalID: proposalID,
            sourceToolID: "engineering.antigravity",
            sourceContractVersion: 1,
            repoRoot: repoRoot,
            affectedFiles: mutations,
            summary: "validator test",
            rationale: "adversarial fixture",
            proposedDiff: diff,
            testPlan: ["swift test"],
            risks: [],
            createdAt: now.addingTimeInterval(-30),
            expiresAt: expiresAt ?? now.addingTimeInterval(300)
        )
    }
}

private struct StubProposalReplayStore: ProposalReplayChecking {
    let proposalIDs: Set<UUID>
    let digests: Set<String>

    init(proposalIDs: Set<UUID> = [], digests: Set<String> = []) {
        self.proposalIDs = proposalIDs
        self.digests = digests
    }

    func contains(proposalID: UUID) throws -> Bool {
        proposalIDs.contains(proposalID)
    }

    func containsDigest(_ digest: String) throws -> Bool {
        digests.contains(digest)
    }
}

private struct StubFilesystemStateBinder: FilesystemStateCapturing {
    let bindings: [FilesystemStateBinding]

    func capture(for mutations: [ValidatedFileMutation]) throws -> [FilesystemStateBinding] {
        bindings
    }

    func revalidate(_ bindings: [FilesystemStateBinding]) throws {}
}
