import XCTest
@testable import Carina

final class ActionActivityJournalTests: XCTestCase {
    func testLifecycleReceiptsUseOriginalRequestCorrelationAndVerifyIntegrity() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let journal = try ActionActivityJournal()
        let vault = AuthorizationTokenVault()
        let dispatcher = CommandDispatcher(replayProtector: ReplayProtector(), approvalTTL: 30, journal: journal)
        guard case let .approvalRequired(challenge) = try await dispatcher.dispatch(envelope: envelope, permission: .execute, now: now) else {
            return XCTFail("Expected challenge")
        }
        let verifier = ApprovalVerifier(vault: vault, journal: journal)
        let token = try await verifier.authorize(challenge: challenge, approved: true, now: now)
        let executor = ProtectedExecutionService(vault: vault, adapter: RecordingAdapter(), journal: journal)
        _ = try await executor.execute(envelope: envelope, authorization: try XCTUnwrap(token), now: now)

        let receipts = await journal.recent()
        XCTAssertEqual(receipts.map(\.status).reversed(), [.prepared, .approved, .executed])
        XCTAssertTrue(receipts.allSatisfy { $0.correlationID == envelope.requestID })
        let isValid = await journal.integrityIsValid()
        XCTAssertTrue(isValid)
    }

    func testDeniedApprovalCreatesReceiptAndCannotExecute() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let journal = try ActionActivityJournal()
        let envelope = makeEnvelope()
        let challenge = ApprovalChallenge(envelope: envelope, expiresAt: now.addingTimeInterval(30))
        let token = try await ApprovalVerifier(vault: AuthorizationTokenVault(), journal: journal)
            .authorize(challenge: challenge, approved: false, now: now)
        XCTAssertNil(token)
        let receipts = await journal.recent()
        XCTAssertEqual(receipts.first?.status, .denied)
    }

    func testJournalRejectsTamperedPersistedHistory() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("receipts.jsonl")
        let journal = try ActionActivityJournal(fileURL: file)
        try await journal.record(challenge: ApprovalChallenge(envelope: makeEnvelope(), expiresAt: Date().addingTimeInterval(30)), status: .prepared)
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
