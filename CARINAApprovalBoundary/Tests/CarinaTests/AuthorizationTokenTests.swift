import XCTest
@testable import Carina

final class AuthorizationTokenTests: XCTestCase {
    func testValidTokenExecutesExactlyOnce() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let vault = AuthorizationTokenVault()
        let verifier = ApprovalVerifier(vault: vault)
        let challenge = ApprovalChallenge(
            envelope: envelope,
            expiresAt: now.addingTimeInterval(30)
        )
        guard let token = try await verifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected an authorization token")
        }
        let adapter = RecordingAdapter()
        let executor = ProtectedExecutionService(vault: vault, adapter: adapter)

        let output = try await executor.execute(
            envelope: envelope,
            authorization: token,
            now: now
        )
        XCTAssertEqual(output, "workspaceSync")
        do {
            _ = try await executor.execute(
                envelope: envelope,
                authorization: token,
                now: now
            )
            XCTFail("Expected consumed-token rejection")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .tokenUnknownOrConsumed)
        }
        let executionCount = await adapter.executionCount
        XCTAssertEqual(executionCount, 1)
    }

    func testExpiredChallengeCannotIssueToken() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let vault = AuthorizationTokenVault()
        let verifier = ApprovalVerifier(vault: vault)
        let challenge = ApprovalChallenge(
            envelope: makeEnvelope(),
            expiresAt: now
        )
        do {
            _ = try await verifier.authorize(
                challenge: challenge,
                approved: true,
                now: now
            )
            XCTFail("Expected expired-challenge rejection")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .challengeExpired)
        }
    }

    func testExpiredTokenCannotExecute() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let vault = AuthorizationTokenVault()
        let verifier = ApprovalVerifier(vault: vault)
        guard let token = try await verifier.authorize(
            challenge: ApprovalChallenge(
                envelope: envelope,
                expiresAt: now.addingTimeInterval(1)
            ),
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected an authorization token")
        }
        let executor = ProtectedExecutionService(
            vault: vault,
            adapter: RecordingAdapter()
        )
        do {
            _ = try await executor.execute(
                envelope: envelope,
                authorization: token,
                now: now.addingTimeInterval(1)
            )
            XCTFail("Expected expired-token rejection")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .tokenExpired)
        }
    }

    func testEnvelopeMutationConsumesAndRejectsToken() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let original = makeEnvelope()
        let mutated = makeEnvelope(payload: [
            "scope": "projects",
            "idempotencyKey": "sync-001"
        ])
        let vault = AuthorizationTokenVault()
        let verifier = ApprovalVerifier(vault: vault)
        guard let token = try await verifier.authorize(
            challenge: ApprovalChallenge(
                envelope: original,
                expiresAt: now.addingTimeInterval(30)
            ),
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected an authorization token")
        }
        let executor = ProtectedExecutionService(
            vault: vault,
            adapter: RecordingAdapter()
        )
        do {
            _ = try await executor.execute(
                envelope: mutated,
                authorization: token,
                now: now
            )
            XCTFail("Expected fingerprint mismatch")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .fingerprintMismatch)
        }
        do {
            _ = try await executor.execute(
                envelope: original,
                authorization: token,
                now: now
            )
            XCTFail("A mismatched token must remain consumed")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .tokenUnknownOrConsumed)
        }
    }

    func testRejectedApprovalIssuesNoToken() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let verifier = ApprovalVerifier(vault: AuthorizationTokenVault())
        let result = try await verifier.authorize(
            challenge: ApprovalChallenge(
                envelope: makeEnvelope(),
                expiresAt: now.addingTimeInterval(30)
            ),
            approved: false,
            now: now
        )
        XCTAssertNil(result)
    }
}
