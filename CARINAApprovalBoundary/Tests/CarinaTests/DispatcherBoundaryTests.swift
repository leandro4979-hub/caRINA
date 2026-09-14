import XCTest
@testable import Carina

final class DispatcherBoundaryTests: XCTestCase {
    func testExecuteDispatchProducesChallengeWithoutExecution() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let verifier = ApprovalVerifier()
        let dispatcher = CommandDispatcher(
            replayProtector: ReplayProtector(),
            approvalVerifier: verifier,
            approvalTTL: 30
        )
        let result = try await dispatcher.dispatch(
            envelope: envelope,
            permission: .execute,
            now: now
        )
        guard case let .approvalRequired(challenge) = result else {
            return XCTFail("Execute must stop at approval")
        }
        XCTAssertEqual(
            challenge.fingerprint,
            ApprovalFingerprint.make(for: envelope)
        )
        XCTAssertEqual(challenge.expiresAt, now.addingTimeInterval(30))
    }

    func testDispatcherRejectsReplayedEnvelope() async throws {
        let verifier = ApprovalVerifier()
        let dispatcher = CommandDispatcher(
            replayProtector: ReplayProtector(),
            approvalVerifier: verifier
        )
        let envelope = makeEnvelope()
        _ = try await dispatcher.dispatch(
            envelope: envelope,
            permission: .execute
        )
        do {
            _ = try await dispatcher.dispatch(
                envelope: envelope,
                permission: .execute
            )
            XCTFail("Expected replay rejection")
        } catch {
            XCTAssertEqual(
                error as? ReplayProtectionError,
                .replayDetected(ReplayKey(envelope: envelope))
            )
        }
    }

    func testDispatcherRejectsFreshEnvelopeThatRepeatsSemanticToolCall() async throws {
        let verifier = ApprovalVerifier()
        let dispatcher = CommandDispatcher(
            replayProtector: ReplayProtector(),
            approvalVerifier: verifier
        )
        let sessionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let first = makeEnvelope(
            sessionID: sessionID,
            sequence: 9,
            nonce: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            payload: [
                "scope": "documents",
                "idempotencyKey": "sync-001"
            ]
        )
        let repeated = makeEnvelope(
            requestID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            sessionID: sessionID,
            sequence: 10,
            nonce: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            payload: [
                "scope": "documents",
                "idempotencyKey": "sync-002"
            ]
        )

        _ = try await dispatcher.dispatch(
            envelope: first,
            permission: .execute
        )

        do {
            _ = try await dispatcher.dispatch(
                envelope: repeated,
                permission: .execute
            )
            XCTFail("Expected duplicate tool-call rejection")
        } catch let error as DuplicateToolCallError {
            XCTAssertEqual(error.code, "duplicate_tool_call")
            XCTAssertEqual(error.toolName, "workspaceSync")
            XCTAssertEqual(
                error.callHash,
                ToolCallHistoryGuard.makeHash(
                    toolName: repeated.request.intentID.rawValue,
                    arguments: repeated.request.payload
                )
            )
        }
    }
}
