import XCTest
@testable import Carina

final class ApprovalBoundaryIntegrationTests: XCTestCase {
    func testReplayApprovalTokenIdempotencyAndAuditEnforceAtMostOnceInvocation() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let journal = try ActionActivityJournal()
        let verifier = ApprovalVerifier(journal: journal)
        let replayProtector = ReplayProtector()
        let dispatcher = CommandDispatcher(
            replayProtector: replayProtector,
            approvalVerifier: verifier,
            approvalTTL: 30
        )
        let idempotencyStore = IdempotencyStore()
        let adapter = RecordingAdapter()
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: idempotencyStore,
            adapter: adapter,
            journal: journal
        )

        guard case let .approvalRequired(challenge) = try await dispatcher.dispatch(
            envelope: envelope,
            permission: .execute,
            now: now
        ) else {
            return XCTFail("Expected approval challenge")
        }

        guard let token = try await verifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected authorization token")
        }

        _ = try await executor.execute(
            envelope: envelope,
            authorization: token,
            now: now
        )

        do {
            _ = try await dispatcher.dispatch(
                envelope: envelope,
                permission: .execute,
                now: now
            )
            XCTFail("Expected replay rejection")
        } catch {
            XCTAssertEqual(
                error as? ReplayProtectionError,
                .replayDetected(ReplayKey(envelope: envelope))
            )
        }

        do {
            _ = try await executor.execute(
                envelope: envelope,
                authorization: token,
                now: now
            )
            XCTFail("Expected consumed-token rejection")
        } catch {
            XCTAssertEqual(
                error as? AuthorizationError,
                .tokenUnknownOrConsumed
            )
        }

        let executionCount = await adapter.executionCount
        let executionStartedCount = await journal.count(status: .executionStarted)
        let executionSucceededCount = await journal.count(status: .executionSucceeded)
        let idempotencyReserved = await idempotencyStore.contains("sync-001")

        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(executionStartedCount, 1)
        XCTAssertEqual(executionSucceededCount, 1)
        XCTAssertTrue(idempotencyReserved)
    }

    func testSameIdempotencyKeyCannotInvokeAdapterTwiceWithFreshAuthorization() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let journal = try ActionActivityJournal()
        let verifier = ApprovalVerifier(journal: journal)
        let dispatcher = CommandDispatcher(
            replayProtector: ReplayProtector(),
            approvalVerifier: verifier
        )
        let idempotencyStore = IdempotencyStore()
        let adapter = RecordingAdapter()
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: idempotencyStore,
            adapter: adapter,
            journal: journal
        )

        let first = makeEnvelope()
        guard case let .approvalRequired(firstChallenge) = try await dispatcher.dispatch(
            envelope: first,
            permission: .execute,
            now: now
        ), let firstToken = try await verifier.authorize(
            challenge: firstChallenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected first authorization")
        }
        _ = try await executor.execute(
            envelope: first,
            authorization: firstToken,
            now: now
        )

        let second = makeEnvelope(
            requestID: UUID(),
            sequence: first.sequence + 1,
            nonce: UUID()
        )
        guard case let .approvalRequired(secondChallenge) = try await dispatcher.dispatch(
            envelope: second,
            permission: .execute,
            now: now
        ), let secondToken = try await verifier.authorize(
            challenge: secondChallenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected second authorization")
        }

        do {
            _ = try await executor.execute(
                envelope: second,
                authorization: secondToken,
                now: now
            )
            XCTFail("Expected duplicate idempotency rejection")
        } catch {
            XCTAssertEqual(
                error as? IdempotencyError,
                .alreadyReserved("sync-001")
            )
        }

        let executionCount = await adapter.executionCount
        XCTAssertEqual(executionCount, 1)
    }
}
