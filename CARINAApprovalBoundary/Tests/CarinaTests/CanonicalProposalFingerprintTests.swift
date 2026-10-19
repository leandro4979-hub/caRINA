import Foundation
import XCTest
@testable import Carina

final class CanonicalProposalFingerprintTests: XCTestCase {
    private let proposalID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testFingerprintIgnoresMutationInputOrder() {
        let first = mutation("/repo/B.swift", operation: .modify)
        let second = mutation("/repo/A.swift", operation: .delete)

        let lhs = fingerprint(mutations: [first, second])
        let rhs = fingerprint(mutations: [second, first])

        XCTAssertEqual(lhs, rhs)
    }

    func testFingerprintChangesWhenFilesystemIdentityChanges() {
        let mutation = mutation("/repo/A.swift", operation: .modify)
        let original = binding(path: "/repo/A.swift", inode: 100)
        let swapped = binding(path: "/repo/A.swift", inode: 101)

        let lhs = fingerprint(mutations: [mutation], bindings: [original])
        let rhs = fingerprint(mutations: [mutation], bindings: [swapped])

        XCTAssertNotEqual(lhs, rhs)
    }

    func testFingerprintChangesWhenOperationChanges() {
        let modify = mutation("/repo/A.swift", operation: .modify)
        let delete = ValidatedFileMutation(
            oldCanonicalPath: "/repo/A.swift",
            newCanonicalPath: nil,
            operation: .delete,
            destructive: true
        )

        XCTAssertNotEqual(
            fingerprint(mutations: [modify]),
            fingerprint(mutations: [delete])
        )
    }

    func testNormalizedDiffDigestTreatsLineEndingsEqually() {
        let unix = "diff --git a/A b/A\n--- a/A\n+++ b/A\n"
        let windows = "diff --git a/A b/A\r\n--- a/A\r\n+++ b/A\r\n"

        XCTAssertEqual(
            CanonicalProposalFingerprint.normalizedDiffDigest(unix),
            CanonicalProposalFingerprint.normalizedDiffDigest(windows)
        )
    }

    func testUnicodeCanonicalEquivalenceProducesSameFingerprint() {
        let composed = "Café.swift"
        let decomposed = "Cafe\u{301}.swift"

        let lhs = fingerprint(repoRoot: "/repo/\(composed)")
        let rhs = fingerprint(repoRoot: "/repo/\(decomposed)")

        XCTAssertEqual(lhs, rhs)
    }

    private func fingerprint(
        repoRoot: String = "/repo",
        mutations: [ValidatedFileMutation] = [],
        bindings: [FilesystemStateBinding] = []
    ) -> String {
        CanonicalProposalFingerprint.make(
            proposalID: proposalID,
            sourceToolID: "engineering.antigravity",
            sourceContractVersion: 1,
            registryVersion: 7,
            repoRoot: repoRoot,
            mutations: mutations,
            filesystemBindings: bindings,
            normalizedDiffDigest: CanonicalProposalFingerprint.normalizedDiffDigest(nil)
        )
    }

    private func mutation(_ path: String, operation: FileOperation) -> ValidatedFileMutation {
        ValidatedFileMutation(
            oldCanonicalPath: operation == .create ? nil : path,
            newCanonicalPath: operation == .delete ? nil : path,
            operation: operation,
            destructive: operation == .delete || operation == .rename
        )
    }

    private func binding(path: String, inode: UInt64) -> FilesystemStateBinding {
        FilesystemStateBinding(
            path: path,
            role: .source,
            expectation: .existing,
            device: 1,
            inode: inode,
            contentSHA256: String(repeating: "a", count: 64),
            parentDevice: 1,
            parentInode: 10
        )
    }
}
