import XCTest
@testable import Carina

final class AuthorizationTokenTests: XCTestCase {
    func testValidTokenExecutesAtMostOnce() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let verifier = ApprovalVerifier()
        let challenge = try await verifier.createChallenge(
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
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(),
            adapter: adapter
        )

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

    func testApprovalChallengeCanMintOnlyOneToken() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let verifier = ApprovalVerifier()
        let challenge = try await verifier.createChallenge(
            envelope: makeEnvelope(),
            expiresAt: now.addingTimeInterval(30)
        )

        _ = try await verifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        )

        do {
            _ = try await verifier.authorize(
                challenge: challenge,
                approved: true,
                now: now
            )
            XCTFail("A consumed approval challenge minted another token")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .challengeUnknownOrConsumed)
        }
    }

    func testExpiredChallengeCannotIssueToken() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let verifier = ApprovalVerifier()
        let challenge = try await verifier.createChallenge(
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
        let verifier = ApprovalVerifier()
        let challenge = try await verifier.createChallenge(
            envelope: envelope,
            expiresAt: now.addingTimeInterval(1)
        )
        guard let token = try await verifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected an authorization token")
        }
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(),
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
        let verifier = ApprovalVerifier()
        let challenge = try await verifier.createChallenge(
            envelope: original,
            expiresAt: now.addingTimeInterval(30)
        )
        guard let token = try await verifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected an authorization token")
        }
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(),
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

    func testRejectedApprovalIssuesNoTokenAndBurnsChallenge() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let verifier = ApprovalVerifier()
        let challenge = try await verifier.createChallenge(
            envelope: makeEnvelope(),
            expiresAt: now.addingTimeInterval(30)
        )
        let result = try await verifier.authorize(
            challenge: challenge,
            approved: false,
            now: now
        )
        XCTAssertNil(result)

        do {
            _ = try await verifier.authorize(
                challenge: challenge,
                approved: true,
                now: now
            )
            XCTFail("Denied challenge must remain burned")
        } catch {
            XCTAssertEqual(error as? AuthorizationError, .challengeUnknownOrConsumed)
        }
    }
}
