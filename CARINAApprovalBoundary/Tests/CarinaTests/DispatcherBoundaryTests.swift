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

    func testChallengeCreationFailureReleasesSemanticReservation() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FailOnceAuthorizationStateStore()
        let verifier = ApprovalVerifier(store: store)
        let dispatcher = CommandDispatcher(
            replayProtector: ReplayProtector(),
            approvalVerifier: verifier,
            approvalTTL: 30
        )
        let first = makeEnvelope()

        do {
            _ = try await dispatcher.dispatch(
                envelope: first,
                permission: .execute,
                now: now
            )
            XCTFail("Expected challenge creation failure")
        } catch {
            XCTAssertEqual(error as? TestAuthorizationStoreError, .insertFailed)
        }

        let retry = makeEnvelope(
            requestID: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            sessionID: first.sessionID,
            sequence: first.sequence + 1,
            nonce: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            payload: [
                "scope": "documents",
                "idempotencyKey": "sync-002"
            ]
        )

        guard case .approvalRequired = try await dispatcher.dispatch(
            envelope: retry,
            permission: .execute,
            now: now.addingTimeInterval(1)
        ) else {
            return XCTFail("Challenge creation failure should permit a fresh retry")
        }
    }
}

private enum TestAuthorizationStoreError: Error, Equatable {
    case insertFailed
}

private actor FailOnceAuthorizationStateStore: AuthorizationStateStore {
    private var shouldFailInsert = true
    private var challenges: [UUID: ApprovalChallenge] = [:]
    private var tokens: [UUID: AuthorizationToken] = [:]

    func insertChallenge(_ challenge: ApprovalChallenge) throws {
        if shouldFailInsert {
            shouldFailInsert = false
            throw TestAuthorizationStoreError.insertFailed
        }
        challenges[challenge.id] = challenge
    }

    func resolveChallenge(
        _ challenge: ApprovalChallenge,
        issuing token: AuthorizationToken?
    ) -> Bool {
        guard challenges[challenge.id] == challenge else { return false }
        challenges[challenge.id] = nil
        if let token { tokens[token.id] = token }
        return true
    }

    func consumeToken(_ token: AuthorizationToken) -> AuthorizationToken? {
        let stored = tokens[token.id]
        tokens[token.id] = nil
        return stored
    }
}
