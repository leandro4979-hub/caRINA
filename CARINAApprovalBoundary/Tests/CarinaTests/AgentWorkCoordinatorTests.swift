import Foundation
import XCTest
@testable import Carina

final class AgentWorkCoordinatorTests: XCTestCase {
    private let coordinator = AgentWorkCoordinator()
    private let taskID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let scopeHash = "sha256:approved-scope"

    func testFourDistinctWorkersAdvanceEvidenceToVerified() throws {
        var item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)

        item = try coordinator.submit(
            report(role: .scout, workerID: "scout-1"),
            outcome: .advance,
            for: item
        )
        XCTAssertEqual(item.stage, .discovered)

        item = try coordinator.submit(
            report(role: .builder, workerID: "builder-1"),
            outcome: .advance,
            for: item
        )
        XCTAssertEqual(item.stage, .implementationProposed)

        item = try coordinator.submit(
            report(role: .securityReviewer, workerID: "security-1"),
            outcome: .advance,
            for: item
        )
        XCTAssertEqual(item.stage, .securityReviewed)

        item = try coordinator.submit(
            report(role: .verifier, workerID: "verifier-1"),
            outcome: .advance,
            for: item
        )

        XCTAssertEqual(item.stage, .verified)
        XCTAssertEqual(item.reports.count, 4)
    }

    func testBuilderCannotSkipScoutDiscovery() {
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)

        XCTAssertThrowsError(
            try coordinator.submit(
                report(role: .builder, workerID: "builder-1"),
                outcome: .advance,
                for: item
            )
        ) { error in
            XCTAssertEqual(
                error as? AgentWorkError,
                .wrongRole(expected: .scout, actual: .builder)
            )
        }
    }

    func testWorkerCannotReviewItsOwnWorkUnderAnotherRole() throws {
        var item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        item = try coordinator.submit(
            report(role: .scout, workerID: "worker-a"),
            outcome: .advance,
            for: item
        )

        XCTAssertThrowsError(
            try coordinator.submit(
                report(role: .builder, workerID: "worker-a"),
                outcome: .advance,
                for: item
            )
        ) { error in
            XCTAssertEqual(
                error as? AgentWorkError,
                .workerSeparationViolation("worker-a")
            )
        }
    }

    func testMissingEvidenceFailsClosed() {
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        let report = AgentEvidenceReport(
            taskID: taskID,
            scopeHash: scopeHash,
            workerID: "scout-1",
            role: .scout,
            claim: "Found the relevant boundary.",
            evidencePointers: [],
            inspected: ["Sources/Carina"]
        )

        XCTAssertThrowsError(
            try coordinator.submit(report, outcome: .advance, for: item)
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .missingEvidence)
        }
    }

    func testScopeMismatchFailsClosed() {
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        let mismatched = AgentEvidenceReport(
            taskID: taskID,
            scopeHash: "sha256:different-scope",
            workerID: "scout-1",
            role: .scout,
            claim: "Found the relevant boundary.",
            evidencePointers: ["file.swift:10"],
            inspected: ["file.swift"]
        )

        XCTAssertThrowsError(
            try coordinator.submit(mismatched, outcome: .advance, for: item)
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .scopeMismatch)
        }
    }

    func testContradictionCanBlockButCannotAdvance() throws {
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        let contradictory = report(
            role: .scout,
            workerID: "scout-1",
            contradictions: ["Tests disagree with the claimed behavior."]
        )

        XCTAssertThrowsError(
            try coordinator.submit(
                contradictory,
                outcome: .advance,
                for: item
            )
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .unresolvedContradictions)
        }

        let blocked = try coordinator.submit(
            contradictory,
            outcome: .block,
            for: item
        )
        XCTAssertEqual(blocked.stage, .blocked)
    }

    func testRequiresReproductionCannotBecomeVerifiedEvidence() throws {
        var item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        item = try coordinator.submit(
            report(role: .scout, workerID: "scout-1"),
            outcome: .advance,
            for: item
        )
        item = try coordinator.submit(
            report(role: .builder, workerID: "builder-1"),
            outcome: .advance,
            for: item
        )
        item = try coordinator.submit(
            report(role: .securityReviewer, workerID: "security-1"),
            outcome: .advance,
            for: item
        )

        XCTAssertThrowsError(
            try coordinator.submit(
                report(
                    role: .verifier,
                    workerID: "verifier-1",
                    requiresReproduction: true
                ),
                outcome: .advance,
                for: item
            )
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .reproductionRequired)
        }
    }

    private func report(
        role: AgentWorkerRole,
        workerID: String,
        contradictions: [String] = [],
        requiresReproduction: Bool = false
    ) -> AgentEvidenceReport {
        AgentEvidenceReport(
            taskID: taskID,
            scopeHash: scopeHash,
            workerID: workerID,
            role: role,
            claim: "Completed the assigned stage.",
            evidencePointers: ["evidence://\(workerID)/result"],
            inspected: ["approved-scope"],
            notInspected: ["outside-approved-scope"],
            contradictions: contradictions,
            requiresReproduction: requiresReproduction,
            submittedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
