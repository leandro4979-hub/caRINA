import Foundation
import XCTest
@testable import Carina

final class ToolCallHistoryGuardTests: XCTestCase {
    func testRejectsDuplicateSemanticCallInSameSession() async throws {
        let guardrail = ToolCallHistoryGuard()
        let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

        let firstHash = try await guardrail.reserve(
            sessionID: sessionID,
            toolName: "workspaceSync",
            arguments: [
                "scope": "documents",
                "idempotencyKey": "sync-001",
                "authorization": "Bearer first-secret"
            ]
        )

        do {
            _ = try await guardrail.reserve(
                sessionID: sessionID,
                toolName: "workspaceSync",
                arguments: [
                    "authorization": "Bearer rotated-secret",
                    "idempotencyKey": "sync-002",
                    "scope": "documents"
                ]
            )
            XCTFail("Expected semantic duplicate rejection")
        } catch let error as DuplicateToolCallError {
            XCTAssertEqual(error.code, "duplicate_tool_call")
            XCTAssertEqual(error.toolName, "workspaceSync")
            XCTAssertEqual(error.callHash, firstHash)
            XCTAssertFalse(error.message.isEmpty)
        }
    }

    func testAllowsDifferentEffectiveArguments() async throws {
        let guardrail = ToolCallHistoryGuard()
        let sessionID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        _ = try await guardrail.reserve(
            sessionID: sessionID,
            toolName: "workspaceSync",
            arguments: ["scope": "documents"]
        )
        _ = try await guardrail.reserve(
            sessionID: sessionID,
            toolName: "workspaceSync",
            arguments: ["scope": "photos"]
        )
    }

    func testAllowsSameCallInDifferentSession() async throws {
        let guardrail = ToolCallHistoryGuard()
        let arguments = ["scope": "documents"]

        _ = try await guardrail.reserve(
            sessionID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            toolName: "workspaceSync",
            arguments: arguments
        )
        _ = try await guardrail.reserve(
            sessionID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            toolName: "workspaceSync",
            arguments: arguments
        )
    }

    func testRejectsRecompiledEquivalentSofaActionPlans() async throws {
        let guardrail = ToolCallHistoryGuard()
        let sessionID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let now = Date(timeIntervalSince1970: 2_000)
        let first = try makeSofaReplyPlan(
            correlationID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            body: "Same external effect",
            now: now
        )
        let second = try makeSofaReplyPlan(
            correlationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            body: "Same external effect",
            now: now.addingTimeInterval(1)
        )

        let firstArguments = try sofaArguments(for: first)
        let secondArguments = try sofaArguments(for: second)
        XCTAssertNotEqual(firstArguments["actionPlan"], secondArguments["actionPlan"])
        XCTAssertNotEqual(first.idempotencyKey, second.idempotencyKey)

        let firstHash = try await guardrail.reserve(
            sessionID: sessionID,
            toolName: "sofaContribution",
            arguments: firstArguments
        )

        do {
            _ = try await guardrail.reserve(
                sessionID: sessionID,
                toolName: "sofaContribution",
                arguments: secondArguments
            )
            XCTFail("Expected equivalent SOFA action plans to be rejected as a semantic duplicate")
        } catch let error as DuplicateToolCallError {
            XCTAssertEqual(error.callHash, firstHash)
        }
    }

    func testHashIsStableAcrossArgumentOrdering() {
        let lhs = ToolCallHistoryGuard.makeHash(
            toolName: "workspaceSync",
            arguments: ["scope": "documents", "mode": "fast"]
        )
        let rhs = ToolCallHistoryGuard.makeHash(
            toolName: "workspaceSync",
            arguments: ["mode": "fast", "scope": "documents"]
        )

        XCTAssertEqual(lhs, rhs)
    }

    private func makeSofaReplyPlan(
        correlationID: UUID,
        body: String,
        now: Date
    ) throws -> ActionPlan {
        try CapabilityFirewall(snapshot: SofaCapabilityCatalog.snapshot).compile(
            correlationID: correlationID,
            userID: "u",
            deviceID: "d",
            capabilityID: SofaCapabilityCatalog.reply.id,
            capabilityVersionMajor: SofaCapabilityCatalog.reply.versionMajor,
            target: "sofa:post-42",
            payload: ["postID": "post-42", "body": body],
            requiredPermissions: ["network.sofa"],
            preflight: ["sofa": true],
            expiresAt: now.addingTimeInterval(60)
        )
    }

    private func sofaArguments(for plan: ActionPlan) throws -> [String: String] {
        [
            "actionPlan": try JSONEncoder().encode(plan).base64EncodedString(),
            "idempotencyKey": plan.idempotencyKey
        ]
    }
}
