import XCTest
@testable import Carina

final class DurableActionLedgerTests: XCTestCase {
    private let capability = Capability(id: "send_work_brief", allowedInputs: ["recipients"], maxRecipients: 1, kind: .commit, risk: .external)

    private func makePlan() throws -> ActionPlan {
        try CapabilityFirewall(capabilities: [capability]).compile(correlationID: UUID(), userID: "u", deviceID: "d", capabilityID: "send_work_brief", target: "alex", payload: ["recipients": "alex"], requiredPermissions: [], preflight: ["bridge": true], expiresAt: Date().addingTimeInterval(60))
    }

    private func temporaryStore() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("carina-ledger-\(UUID().uuidString).json") }

    func testReservationAtomicallyCreatesStableOutboxEntryAndSurvivesRestart() async throws {
        let url = temporaryStore(); defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        let plan = try makePlan()
        let first = try DurableActionLedger(storeURL: url)
        let reservation = try await first.reserve(plan)
        XCTAssertEqual(reservation, .approved)
        let restart = try DurableActionLedger(storeURL: url)
        let pending = try await restart.pendingOutbox()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].id, plan.idempotencyKey)
        XCTAssertEqual(pending[0].plan.lockedArtifactHash, plan.lockedArtifactHash)
    }

    func testConcurrentLedgerInstancesHaveOneReservationWinner() async throws {
        let url = temporaryStore(); defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        let plan = try makePlan()
        let left = try DurableActionLedger(storeURL: url); let right = try DurableActionLedger(storeURL: url)
        async let a = left.reserve(plan); async let b = right.reserve(plan)
        let first = try await a; let second = try await b
        XCTAssertEqual(first, .approved); XCTAssertEqual(second, .approved)
        let pending = try await left.pendingOutbox()
        XCTAssertEqual(pending.count, 1)
    }

    func testRestartRecoveryDoesNotRedeliverCompletedEffect() async throws {
        let url = temporaryStore(); defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        let plan = try makePlan(); let ledger = try DurableActionLedger(storeURL: url)
        _ = try await ledger.reserve(plan)
        let dispatchID = try await ledger.pendingOutbox().first!.id
        try await ledger.beginDispatch(dispatchID: dispatchID)
        try await ledger.complete(dispatchID: dispatchID, verified: true)
        let restart = try DurableActionLedger(storeURL: url)
        let pending = try await restart.pendingOutbox()
        let state = try await restart.state(for: plan)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(state, .verified)
    }

    func testPersistedPlanMutationIsRejectedBeforeDispatch() async throws {
        let url = temporaryStore(); defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("lock")) }
        let plan = try makePlan(); let ledger = try DurableActionLedger(storeURL: url)
        _ = try await ledger.reserve(plan)
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "alex", with: "evil")
        try text.data(using: .utf8)!.write(to: url)
        await XCTAssertThrowsErrorAsync(try await ledger.pendingOutbox()) { error in
            XCTAssertEqual(error as? DurableLedgerError, .tamperedPlan)
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void) async {
    do { _ = try await expression(); XCTFail("expected error") } catch { handler(error) }
}
