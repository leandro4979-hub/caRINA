import Foundation
import XCTest
@testable import Carina

/// Approval-denial fixture: represents the earliest possible Appium transport boundary.
/// No network requests or real device actions are performed.
final class DeviceAuthorizationPreflightTests: XCTestCase {
    func testMismatchedTargetDeniesBeforeAdapterInvocation() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let verifier = ApprovalVerifier()
        let dispatcher = CommandDispatcher(
            replayProtector: ReplayProtector(),
            approvalVerifier: verifier
        )
        let transportSpy = RecordingAdapter()
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(),
            adapter: transportSpy
        )
        let approvedEnvelope = makeEnvelope(target: "test-device-A")
        guard case let .approvalRequired(challenge) = try await dispatcher.dispatch(
            envelope: approvedEnvelope,
            permission: .execute,
            now: now
        ), let token = try await verifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected exact-action approval")
        }

        let changedTarget = makeEnvelope(target: "test-device-B")
        do {
            _ = try await executor.execute(
                envelope: changedTarget,
                authorization: token,
                now: now
            )
            XCTFail("Expected authorization mismatch before adapter invocation")
        } catch {
            // Any authorization rejection is acceptable; no adapter call is.
        }

        let transportCalls = await transportSpy.executionCount
        XCTAssertEqual(transportCalls, 0, "No Appium transport may be contacted before exact-action authorization")
    }
}
