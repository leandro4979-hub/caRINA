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
}
