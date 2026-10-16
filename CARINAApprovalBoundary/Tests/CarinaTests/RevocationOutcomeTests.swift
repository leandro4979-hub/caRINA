import Foundation
import XCTest
@testable import Carina

final class RevocationOutcomeTests: XCTestCase {
    func testBlockedReceiverToGatewayUpdateStaysIncompleteAndFencesStaleCapability() throws {
        let deadline = Date(timeIntervalSince1970: 1_000)
        var monitor = RevocationOutcomeMonitor(
            revocationID: UUID(),
            sequence: 42,
            gatewayIDs: ["gateway-a", "gateway-b"],
            observationDeadline: deadline
        )
        var committedEffects = 0

        monitor.recordReceiverPersistence()
        try monitor.recordGatewayInstallation(gatewayID: "gateway-a", sequence: 42)
        try monitor.recordEffectObservation(
            gatewayID: "gateway-a",
            observation: .noCommittedEffect
        )

        // Fault injection: delivery from the receiver to gateway-b is blocked.
        if !monitor.isGatewayFenced("gateway-b") {
            committedEffects += 1
        }

        XCTAssertTrue(monitor.isGatewayFenced("gateway-b"))
        XCTAssertEqual(committedEffects, 0)
        XCTAssertEqual(
            monitor.completion(at: deadline.addingTimeInterval(1)),
            .incomplete
        )

        // Recovery requires a fresh installation receipt and independent
        // effect evidence. Either one alone must leave the transaction open.
        try monitor.recordGatewayInstallation(gatewayID: "gateway-b", sequence: 42)
        XCTAssertFalse(monitor.isGatewayFenced("gateway-b"))
        XCTAssertEqual(
            monitor.completion(at: deadline.addingTimeInterval(1)),
            .incomplete
        )

        try monitor.recordEffectObservation(
            gatewayID: "gateway-b",
            observation: .noCommittedEffect
        )
        XCTAssertEqual(
            monitor.completion(at: deadline.addingTimeInterval(1)),
            .effectsVerified
        )
    }

    func testStaleInstallationReceiptIsRejected() throws {
        var monitor = makeMonitor()
        monitor.recordReceiverPersistence()

        XCTAssertThrowsError(
            try monitor.recordGatewayInstallation(gatewayID: "gateway-a", sequence: 41)
        ) { error in
            XCTAssertEqual(
                error as? RevocationOutcomeError,
                .staleInstallation(gatewayID: "gateway-a", installedSequence: 41)
            )
        }
        XCTAssertTrue(monitor.isGatewayFenced("gateway-a"))
    }

    func testCommittedEffectViolationIsSticky() throws {
        let deadline = Date(timeIntervalSince1970: 1_000)
        var monitor = makeMonitor(deadline: deadline)
        monitor.recordReceiverPersistence()
        try monitor.recordGatewayInstallation(gatewayID: "gateway-a", sequence: 42)
        try monitor.recordEffectObservation(
            gatewayID: "gateway-a",
            observation: .committedEffect
        )
        try monitor.recordEffectObservation(
            gatewayID: "gateway-a",
            observation: .noCommittedEffect
        )

        XCTAssertEqual(
            monitor.completion(at: deadline.addingTimeInterval(1)),
            .violated
        )
    }

    func testDuplicateEvidenceIsIdempotentAndWindowMustClose() throws {
        let deadline = Date(timeIntervalSince1970: 1_000)
        var monitor = makeMonitor(deadline: deadline)
        monitor.recordReceiverPersistence()
        monitor.recordReceiverPersistence()
        try monitor.recordGatewayInstallation(gatewayID: "gateway-a", sequence: 42)
        try monitor.recordGatewayInstallation(gatewayID: "gateway-a", sequence: 42)
        try monitor.recordEffectObservation(
            gatewayID: "gateway-a",
            observation: .noCommittedEffect
        )
        try monitor.recordEffectObservation(
            gatewayID: "gateway-a",
            observation: .noCommittedEffect
        )

        XCTAssertEqual(
            monitor.completion(at: deadline.addingTimeInterval(-1)),
            .incomplete
        )
        XCTAssertEqual(
            monitor.completion(at: deadline),
            .effectsVerified
        )
    }

    func testEmptyGatewayPopulationFailsClosed() {
        let deadline = Date(timeIntervalSince1970: 1_000)
        var monitor = RevocationOutcomeMonitor(
            revocationID: UUID(),
            sequence: 42,
            gatewayIDs: [],
            observationDeadline: deadline
        )
        monitor.recordReceiverPersistence()

        XCTAssertEqual(
            monitor.completion(at: deadline.addingTimeInterval(1)),
            .incomplete
        )
    }

    private func makeMonitor(
        deadline: Date = Date(timeIntervalSince1970: 1_000)
    ) -> RevocationOutcomeMonitor {
        RevocationOutcomeMonitor(
            revocationID: UUID(),
            sequence: 42,
            gatewayIDs: ["gateway-a"],
            observationDeadline: deadline
        )
    }
}
