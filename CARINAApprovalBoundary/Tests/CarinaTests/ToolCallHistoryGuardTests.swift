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
}
