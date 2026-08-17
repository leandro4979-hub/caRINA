import XCTest
@testable import Carina

final class SofaBridgeTests: XCTestCase {
    func testReadOperationsRemainReadOnlyAndContributionOperationsRequireExecutionPermission() {
        assertRead(SofaPolicy.permission(for: .search))
        assertRead(SofaPolicy.permission(for: .getPost))
        assertExecute(SofaPolicy.permission(for: .vote))
        assertExecute(SofaPolicy.permission(for: .verify))
        assertExecute(SofaPolicy.permission(for: .reply))
    }

    func testContributionAdapterRejectsApprovalTargetDriftBeforeCallingTransport() async throws {
        let transport = RecordingSofaTransport()
        let adapter = SofaContributionAdapter(transport: transport)
        let request = CommandRequest(
            intentID: .sofaContribution,
            payload: [
                "action": "vote",
                "postID": "post-123",
                "value": "1"
            ],
            target: "sofa:different-post"
        )

        do {
            _ = try await adapter.execute(request)
            XCTFail("Expected target mismatch rejection")
        } catch let error as SofaError {
            guard case .invalidConfiguration = error else {
                return XCTFail("Unexpected SOFA error: \(error)")
            }
        }

        let calls = await transport.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testProtectedExecutionRoutesApprovedVoteExactlyOnce() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let postID = "post-456"
        let request = CommandRequest(
            intentID: .sofaContribution,
            payload: [
                "action": "vote",
                "postID": postID,
                "value": "1",
                "idempotencyKey": "sofa-vote-post-456"
            ],
            target: SofaContributionAdapter<RecordingSofaTransport>.target(postID: postID)
        )
        let envelope = CommandEnvelope(
            version: 1,
            requestID: UUID(),
            sessionID: UUID(),
            sequence: 1,
            nonce: UUID(),
            source: .userInterface,
            request: request
        )

        let journal = try ActionActivityJournal()
        let verifier = ApprovalVerifier(journal: journal)
        let dispatcher = CommandDispatcher(
            replayProtector: ReplayProtector(),
            approvalVerifier: verifier,
            approvalTTL: 30
        )
        let transport = RecordingSofaTransport()
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(),
            adapter: SofaContributionAdapter(transport: transport),
            journal: journal
        )

        guard case let .approvalRequired(challenge) = try await dispatcher.dispatch(
            envelope: envelope,
            permission: SofaPolicy.permission(for: .vote),
            now: now
        ) else {
            return XCTFail("Expected SOFA vote to require approval")
        }
        guard let token = try await verifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected approval token")
        }

        let receipt = try await executor.execute(
            envelope: envelope,
            authorization: token,
            now: now
        )

        XCTAssertEqual(receipt.statusCode, 200)
        let calls = await transport.calls
        XCTAssertEqual(calls, [.vote(postID: postID, value: 1)])
        let executionSucceededCount = await journal.count(status: .executionSucceeded)
        XCTAssertEqual(executionSucceededCount, 1)
    }

    func testVerificationAndReplyPayloadsAreTypedBeforeTransport() async throws {
        let transport = RecordingSofaTransport()
        let adapter = SofaContributionAdapter(transport: transport)

        let verification = CommandRequest(
            intentID: .sofaContribution,
            payload: [
                "action": "verify",
                "postID": "post-v",
                "outcome": "worked_with_changes",
                "feedback": "Required one configuration adjustment."
            ],
            target: SofaContributionAdapter<RecordingSofaTransport>.target(postID: "post-v")
        )
        _ = try await adapter.execute(verification)

        let reply = CommandRequest(
            intentID: .sofaContribution,
            payload: [
                "action": "reply",
                "postID": "post-r",
                "body": "Observed the same behavior on macOS."
            ],
            target: SofaContributionAdapter<RecordingSofaTransport>.target(postID: "post-r")
        )
        _ = try await adapter.execute(reply)

        let calls = await transport.calls
        XCTAssertEqual(
            calls,
            [
                .verify(
                    postID: "post-v",
                    outcome: .workedWithChanges,
                    feedback: "Required one configuration adjustment."
                ),
                .reply(postID: "post-r", body: "Observed the same behavior on macOS.")
            ]
        )
    }

    private func assertRead(_ permission: CommandPermission, file: StaticString = #filePath, line: UInt = #line) {
        guard case .read = permission else {
            return XCTFail("Expected read permission", file: file, line: line)
        }
    }

    private func assertExecute(_ permission: CommandPermission, file: StaticString = #filePath, line: UInt = #line) {
        guard case .execute = permission else {
            return XCTFail("Expected execute permission", file: file, line: line)
        }
    }
}

private actor RecordingSofaTransport: SofaContributionTransport {
    enum Call: Sendable, Equatable {
        case vote(postID: String, value: Int)
        case verify(postID: String, outcome: SofaVerificationOutcome, feedback: String)
        case reply(postID: String, body: String)
    }

    private(set) var calls: [Call] = []

    func vote(postID: String, value: Int) async throws -> SofaMutationReceipt {
        calls.append(.vote(postID: postID, value: value))
        return SofaMutationReceipt(statusCode: 200, responseBody: Data())
    }

    func verify(
        postID: String,
        outcome: SofaVerificationOutcome,
        feedback: String
    ) async throws -> SofaMutationReceipt {
        calls.append(.verify(postID: postID, outcome: outcome, feedback: feedback))
        return SofaMutationReceipt(statusCode: 201, responseBody: Data())
    }

    func reply(postID: String, body: String) async throws -> SofaMutationReceipt {
        calls.append(.reply(postID: postID, body: body))
        return SofaMutationReceipt(statusCode: 201, responseBody: Data())
    }
}
