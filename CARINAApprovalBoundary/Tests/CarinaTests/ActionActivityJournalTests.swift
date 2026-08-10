import XCTest
@testable import Carina

final class ActionActivityJournalTests: XCTestCase {
    func testLifecycleReceiptsUseOriginalRequestCorrelationAndVerifyIntegrity() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let journal = try ActionActivityJournal()
        let verifier = ApprovalVerifier(journal: journal)
        let dispatcher = CommandDispatcher(
            replayProtector: ReplayProtector(),
            approvalVerifier: verifier,
            approvalTTL: 30
        )
        guard case let .approvalRequired(challenge) = try await dispatcher.dispatch(
            envelope: envelope,
            permission: .execute,
            now: now
        ) else {
            return XCTFail("Expected challenge")
        }
        let token = try await verifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        )
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(),
            adapter: RecordingAdapter(),
            journal: journal
        )
        _ = try await executor.execute(
            envelope: envelope,
            authorization: try XCTUnwrap(token),
            now: now
        )

        let receipts = await journal.recent()
        XCTAssertEqual(
            receipts.map(\.status).reversed(),
            [.prepared, .approved, .executionStarted, .executionSucceeded]
        )
        XCTAssertTrue(receipts.allSatisfy { $0.correlationID == envelope.requestID })
        XCTAssertTrue(await journal.integrityIsValid())
    }

    func testDeniedApprovalCreatesReceiptAndCannotBeReused() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let journal = try ActionActivityJournal()
        let verifier = ApprovalVerifier(journal: journal)
        let challenge = try await verifier.createChallenge(
            envelope: makeEnvelope(),
            expiresAt: now.addingTimeInterval(30)
        )
        let token = try await verifier.authorize(
            challenge: challenge,
            approved: false,
            now: now
        )
        XCTAssertNil(token)
        XCTAssertEqual((await journal.recent()).first?.status, .denied)

        do {
            _ = try await verifier.authorize(
                challenge: challenge,
                approved: true,
                now: now
            )
            XCTFail("Denied challenge should be consumed")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .challengeUnknownOrConsumed)
        }
    }

    func testJournalRejectsTamperedPersistedHistory() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("receipts.jsonl")
        let journal = try ActionActivityJournal(fileURL: file)
        let verifier = ApprovalVerifier()
        let envelope = makeEnvelope()
        let challenge = try await verifier.createChallenge(
            envelope: envelope,
            expiresAt: Date().addingTimeInterval(30)
        )
        try await journal.record(challenge: challenge, status: .prepared)
        var line = try String(contentsOf: file, encoding: .utf8)
        line = line.replacingOccurrences(of: "prepared", with: "approved")
        try line.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ActionActivityJournal(fileURL: file)) { error in
            XCTAssertEqual(error as? JournalError, .integrityFailure)
        }
    }

    func testTargetChangeInvalidatesFingerprint() {
        let original = makeEnvelope(payload: ["scope": "projects"], target: "Project Atlas")
        let changed = makeEnvelope(payload: ["scope": "projects"], target: "Project Borealis")
        XCTAssertNotEqual(ApprovalFingerprint.make(for: original), ApprovalFingerprint.make(for: changed))
    }

    func testTrustDashboardRetainsOnlyPresentedTrustState() async throws {
        let journal = try ActionActivityJournal()
        let dashboard = TrustDashboard(
            privateModeEnabled: true,
            bridgeState: "connected",
            permissionIssues: ["Calendar access denied"],
            recentReceipts: await journal.recent()
        )
        XCTAssertTrue(dashboard.privateModeEnabled)
        XCTAssertEqual(dashboard.permissionIssues, ["Calendar access denied"])
        XCTAssertTrue(dashboard.recentReceipts.isEmpty)
    }
}
