import Foundation
import XCTest
@testable import Carina

final class SofaBridgeTests: XCTestCase {
    func testReadOperationsRemainReadOnlyAndContributionOperationsRequireExecutionPermission() {
        assertRead(SofaPolicy.permission(for: .search))
        assertRead(SofaPolicy.permission(for: .getPost))
        assertExecute(SofaPolicy.permission(for: .vote))
        assertExecute(SofaPolicy.permission(for: .verify))
        assertExecute(SofaPolicy.permission(for: .reply))

        XCTAssertEqual(SofaCapabilityCatalog.search.kind, .read)
        XCTAssertEqual(SofaCapabilityCatalog.vote.kind, .commit)
        XCTAssertEqual(SofaCapabilityCatalog.vote.risk, .external)
    }

    func testRegistryRejectsVoteParameterSmuggling() throws {
        let firewall = CapabilityFirewall(snapshot: SofaCapabilityCatalog.snapshot)
        XCTAssertThrowsError(
            try firewall.compile(
                correlationID: UUID(),
                userID: "u",
                deviceID: "d",
                capabilityID: SofaCapabilityCatalog.vote.id,
                target: "sofa:reply-123",
                payload: ["postID": "reply-123", "value": "1", "reply_id": "root-456"],
                requiredPermissions: ["network.sofa"],
                preflight: ["sofa": true],
                expiresAt: Date().addingTimeInterval(60)
            )
        ) { error in
            XCTAssertEqual(error as? CapabilityError, .unknownInput("reply_id"))
        }
    }

    func testContributionAdapterRejectsApprovalTargetDriftBeforeCallingTransport() async throws {
        let now = Date()
        let transport = RecordingSofaTransport()
        let adapter = SofaContributionAdapter(transport: transport)
        let plan = try makePlan(
            capability: SofaCapabilityCatalog.vote,
            postID: "post-123",
            payload: ["postID": "post-123", "value": "1"],
            now: now
        )
        let lockedRequest = try adapter.commandRequest(for: plan, now: now)
        let driftedRequest = CommandRequest(
            intentID: lockedRequest.intentID,
            payload: lockedRequest.payload,
            target: "sofa:different-post"
        )

        do {
            _ = try await adapter.execute(driftedRequest)
            XCTFail("Expected target mismatch rejection")
        } catch let error as SofaError {
            XCTAssertEqual(error, .invalidActionPlan)
        }

        let calls = await transport.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testContributionAdapterRejectsUnapprovedRegistrySnapshot() throws {
        let unreviewed = CapabilityRegistrySnapshot(
            id: "unreviewed-sofa",
            capabilities: [SofaCapabilityCatalog.vote]
        )
        let plan = try CapabilityFirewall(snapshot: unreviewed).compile(
            correlationID: UUID(),
            userID: "u",
            deviceID: "d",
            capabilityID: SofaCapabilityCatalog.vote.id,
            target: "sofa:post-unauthorized",
            payload: ["postID": "post-unauthorized", "value": "1"],
            requiredPermissions: ["network.sofa"],
            preflight: ["sofa": true],
            expiresAt: Date().addingTimeInterval(60)
        )
        let adapter = SofaContributionAdapter(transport: RecordingSofaTransport())

        XCTAssertThrowsError(try adapter.commandRequest(for: plan)) { error in
            XCTAssertEqual(error as? SofaError, .unapprovedRegistrySnapshot("unreviewed-sofa"))
        }
    }

    func testProtectedExecutionRoutesApprovedLockedVotePlanExactlyOnce() async throws {
        let now = Date()
        let postID = "post-456"
        let transport = RecordingSofaTransport()
        let adapter = SofaContributionAdapter(transport: transport)
        let plan = try makePlan(
            capability: SofaCapabilityCatalog.vote,
            postID: postID,
            payload: ["postID": postID, "value": "1"],
            now: now
        )
        let request = try adapter.commandRequest(for: plan, now: now)
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
        let executor = ProtectedExecutionService(
            approvalVerifier: verifier,
            idempotencyStore: IdempotencyStore(),
            adapter: adapter,
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
        XCTAssertEqual(request.payload["idempotencyKey"], plan.idempotencyKey)
        XCTAssertNotNil(request.payload["actionPlan"])
    }

    func testVerificationAndReplyPlansAreTypedBeforeTransport() async throws {
        let now = Date()
        let transport = RecordingSofaTransport()
        let adapter = SofaContributionAdapter(transport: transport)

        let verificationPlan = try makePlan(
            capability: SofaCapabilityCatalog.verify,
            postID: "post-v",
            payload: [
                "postID": "post-v",
                "outcome": "worked_with_changes",
                "feedback": "Required one configuration adjustment."
            ],
            now: now
        )
        _ = try await adapter.execute(adapter.commandRequest(for: verificationPlan, now: now))

        let replyPlan = try makePlan(
            capability: SofaCapabilityCatalog.reply,
            postID: "post-r",
            payload: [
                "postID": "post-r",
                "body": "Observed the same behavior on macOS."
            ],
            now: now
        )
        _ = try await adapter.execute(adapter.commandRequest(for: replyPlan, now: now))

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

    private func makePlan(
        capability: Capability,
        postID: String,
        payload: [String: String],
        now: Date
    ) throws -> ActionPlan {
        try CapabilityFirewall(snapshot: SofaCapabilityCatalog.snapshot).compile(
            correlationID: UUID(),
            userID: "u",
            deviceID: "d",
            capabilityID: capability.id,
            capabilityVersionMajor: capability.versionMajor,
            target: SofaContributionAdapter<RecordingSofaTransport>.target(postID: postID),
            payload: payload,
            requiredPermissions: ["network.sofa"],
            preflight: ["sofa": true],
            expiresAt: now.addingTimeInterval(60)
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
