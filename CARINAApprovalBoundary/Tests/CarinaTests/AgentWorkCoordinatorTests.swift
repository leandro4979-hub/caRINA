import Foundation
import XCTest
@testable import Carina

final class AgentWorkCoordinatorTests: XCTestCase {
    private let taskID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private let scopeHash = "sha256:approved-scope"

    func testFourDistinctWorkersAdvanceEvidenceToVerified() throws {
        let configuration = try configured()
        var item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)

        item = try submit(
            report(evidenceID: "scout-1"),
            as: "scout-1",
            for: item,
            using: configuration
        )
        XCTAssertEqual(item.stage, .discovered)

        item = try submit(
            report(evidenceID: "builder-1"),
            as: "builder-1",
            for: item,
            using: configuration
        )
        XCTAssertEqual(item.stage, .implementationProposed)

        item = try submit(
            report(evidenceID: "security-1"),
            as: "security-1",
            for: item,
            using: configuration
        )
        XCTAssertEqual(item.stage, .securityReviewed)

        item = try submit(
            report(evidenceID: "verifier-1"),
            as: "verifier-1",
            for: item,
            using: configuration
        )

        XCTAssertEqual(item.stage, .verified)
        XCTAssertEqual(
            item.reports.map(\.authenticatedWorkerID),
            ["scout-1", "builder-1", "security-1", "verifier-1"]
        )
        XCTAssertEqual(
            item.reports.map(\.assignedRole),
            [.scout, .builder, .securityReviewer, .verifier]
        )
        XCTAssertEqual(
            item.reports.map(\.outcome),
            [.advance, .advance, .advance, .advance]
        )
        XCTAssertEqual(
            item.reports.map(\.fromStage),
            [.queued, .discovered, .implementationProposed, .securityReviewed]
        )
        XCTAssertEqual(
            item.reports.map(\.toStage),
            [.discovered, .implementationProposed, .securityReviewed, .verified]
        )
    }

    func testBuilderCannotSkipScoutDiscovery() throws {
        let configuration = try configured()
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)

        XCTAssertThrowsError(
            try submit(
                report(evidenceID: "builder-1"),
                as: "builder-1",
                for: item,
                using: configuration
            )
        ) { error in
            XCTAssertEqual(
                error as? AgentWorkError,
                .wrongRole(expected: .scout, actual: .builder)
            )
        }
    }

    func testAuthenticatedWorkerCannotClaimAnotherRole() throws {
        let configuration = try configured()
        var item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        item = try submit(
            report(evidenceID: "worker-a"),
            as: "worker-a",
            for: item,
            using: configuration
        )

        XCTAssertThrowsError(
            try submit(
                report(evidenceID: "worker-a-second-report"),
                as: "worker-a",
                for: item,
                using: configuration
            )
        ) { error in
            XCTAssertEqual(
                error as? AgentWorkError,
                .wrongRole(expected: .builder, actual: .scout)
            )
        }
    }

    func testCredentialFromDifferentCoordinatorFailsClosed() throws {
        let configuration = try configured()
        let foreign = try AgentWorkCoordinator.configure(
            workerRoles: ["scout-1": .scout]
        )
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)

        XCTAssertThrowsError(
            try configuration.coordinator.submit(
                report(evidenceID: "foreign"),
                credential: try credential("scout-1", from: foreign),
                outcome: .advance,
                for: item
            )
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .unknownWorkerCredential)
        }
    }

    func testEmptyWorkerRegistryFailsClosed() {
        XCTAssertThrowsError(
            try AgentWorkCoordinator.configure(workerRoles: [:])
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .emptyWorkerRegistry)
        }
    }

    func testBlankRegisteredWorkerIdentityFailsClosed() {
        XCTAssertThrowsError(
            try AgentWorkCoordinator.configure(workerRoles: ["  ": .scout])
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .invalidRegisteredWorkerID)
        }
    }

    func testMissingEvidenceFailsClosed() throws {
        let configuration = try configured()
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        let report = AgentEvidenceReport(
            taskID: taskID,
            scopeHash: scopeHash,
            claim: "Found the relevant boundary.",
            evidencePointers: [],
            inspected: ["Sources/Carina"]
        )

        XCTAssertThrowsError(
            try submit(
                report,
                as: "scout-1",
                for: item,
                using: configuration
            )
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .missingEvidence)
        }
    }

    func testScopeMismatchFailsClosed() throws {
        let configuration = try configured()
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        let mismatched = AgentEvidenceReport(
            taskID: taskID,
            scopeHash: "sha256:different-scope",
            claim: "Found the relevant boundary.",
            evidencePointers: ["file.swift:10"],
            inspected: ["file.swift"]
        )

        XCTAssertThrowsError(
            try submit(
                mismatched,
                as: "scout-1",
                for: item,
                using: configuration
            )
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .scopeMismatch)
        }
    }

    func testContradictionCanBlockButCannotAdvance() throws {
        let configuration = try configured()
        let item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        let contradictory = report(
            evidenceID: "scout-1",
            contradictions: ["Tests disagree with the claimed behavior."]
        )

        XCTAssertThrowsError(
            try submit(
                contradictory,
                as: "scout-1",
                for: item,
                using: configuration
            )
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .unresolvedContradictions)
        }

        let blocked = try submit(
            contradictory,
            as: "scout-1",
            outcome: .block,
            for: item,
            using: configuration
        )
        XCTAssertEqual(blocked.stage, .blocked)
        XCTAssertEqual(blocked.reports.first?.outcome, .block)
        XCTAssertEqual(blocked.reports.first?.fromStage, .queued)
        XCTAssertEqual(blocked.reports.first?.toStage, .blocked)
    }

    func testRequiresReproductionCannotBecomeVerifiedEvidence() throws {
        let configuration = try configured()
        var item = AgentWorkItem(taskID: taskID, scopeHash: scopeHash)
        item = try submit(
            report(evidenceID: "scout-1"),
            as: "scout-1",
            for: item,
            using: configuration
        )
        item = try submit(
            report(evidenceID: "builder-1"),
            as: "builder-1",
            for: item,
            using: configuration
        )
        item = try submit(
            report(evidenceID: "security-1"),
            as: "security-1",
            for: item,
            using: configuration
        )

        XCTAssertThrowsError(
            try submit(
                report(
                    evidenceID: "verifier-1",
                    requiresReproduction: true
                ),
                as: "verifier-1",
                for: item,
                using: configuration
            )
        ) { error in
            XCTAssertEqual(error as? AgentWorkError, .reproductionRequired)
        }
    }

    private func configured() throws -> AgentWorkCoordinatorConfiguration {
        try AgentWorkCoordinator.configure(workerRoles: [
            "scout-1": .scout,
            "builder-1": .builder,
            "security-1": .securityReviewer,
            "verifier-1": .verifier,
            "worker-a": .scout,
        ])
    }

    private func credential(
        _ workerID: String,
        from configuration: AgentWorkCoordinatorConfiguration
    ) throws -> AgentWorkerCredential {
        try XCTUnwrap(configuration.credentials[workerID])
    }

    private func submit(
        _ report: AgentEvidenceReport,
        as workerID: String,
        outcome: AgentSubmissionOutcome = .advance,
        for item: AgentWorkItem,
        using configuration: AgentWorkCoordinatorConfiguration
    ) throws -> AgentWorkItem {
        try configuration.coordinator.submit(
            report,
            credential: credential(workerID, from: configuration),
            outcome: outcome,
            for: item
        )
    }

    private func report(
        evidenceID: String,
        contradictions: [String] = [],
        requiresReproduction: Bool = false
    ) -> AgentEvidenceReport {
        AgentEvidenceReport(
            taskID: taskID,
            scopeHash: scopeHash,
            claim: "Completed the assigned stage.",
            evidencePointers: ["evidence://\(evidenceID)/result"],
            inspected: ["approved-scope"],
            notInspected: ["outside-approved-scope"],
            contradictions: contradictions,
            requiresReproduction: requiresReproduction,
            submittedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
