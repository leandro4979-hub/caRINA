import Foundation
import XCTest
@testable import Carina

/// Regression coverage for the proposed LocalSupervisorActionAdapter boundary.
/// No supervisor execution capability is registered by these tests.
final class LocalSupervisorAuthorizationTests: XCTestCase {
    func testUnapprovedSupervisorActionNeverReachesAdapter() async throws {
        let store = InMemoryApprovalStateStore()
        let verifier = ApprovalVerifier(store: store)
        let adapter = RecordingAdapter()
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(store: store),
            adapter: adapter
        )
        let envelope = makeEnvelope(
            payload: ["scope": "documents", "idempotencyKey": UUID().uuidString],
            target: "Local supervisor proposed action"
        )
        let unissuedToken = AuthorizationToken(
            id: UUID(),
            fingerprint: ApprovalFingerprint.make(for: envelope),
            expiresAt: Date().addingTimeInterval(60)
        )

        do {
            _ = try await executor.execute(
                envelope: envelope,
                authorization: unissuedToken
            )
            XCTFail("An unissued token authorized supervisor execution")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .tokenUnknownOrConsumed)
        }
        let executions = await adapter.executionCount
        XCTAssertEqual(executions, 0, "Adapter must not run without approved token")
    }

    func testAlteredSupervisorActionNeverReachesAdapter() async throws {
        let store = InMemoryApprovalStateStore()
        let verifier = ApprovalVerifier(store: store)
        let adapter = RecordingAdapter()
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(store: store),
            adapter: adapter
        )
        let original = makeEnvelope(
            payload: ["scope": "documents", "idempotencyKey": UUID().uuidString],
            target: "Approved supervisor action"
        )
        let challenge = try await verifier.createChallenge(
            envelope: original,
            expiresAt: Date().addingTimeInterval(60)
        )
        guard let token = try await verifier.authorize(challenge: challenge, approved: true) else {
            return XCTFail("Expected approved token")
        }
        let changed = CommandEnvelope(
            version: original.version,
            requestID: original.requestID,
            sessionID: original.sessionID,
            sequence: original.sequence,
            nonce: original.nonce,
            source: original.source,
            request: CommandRequest(
                intentID: original.request.intentID,
                payload: original.request.payload,
                target: "Different supervisor action"
            )
        )

        do {
            _ = try await executor.execute(envelope: changed, authorization: token)
            XCTFail("Token authorized a different action")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .fingerprintMismatch)
        }
        let executions = await adapter.executionCount
        XCTAssertEqual(executions, 0, "Action mismatch must fail before adapter")
    }
}
