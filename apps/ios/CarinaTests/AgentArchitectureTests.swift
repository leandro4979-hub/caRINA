import Foundation
import XCTest
@testable import Carina

final class AgentArchitectureTests: XCTestCase {
    private let engine = CommandPermissionEngine()

    func testReadAndPrepareCommandsAreAllowed() {
        XCTAssertEqual(engine.authorize(CommandRequest(name: "system.status", payload: [:])), .allow)
        XCTAssertEqual(
            engine.authorize(CommandRequest(name: "shortcut.prepare", payload: ["shortcutName": "Test"])),
            .allow
        )
    }

    func testExecuteRequiresApproval() {
        let decision = engine.authorize(
            CommandRequest(name: "shortcut.run", payload: ["shortcutName": "Carina Command Center"])
        )
        guard case .requireApproval = decision else {
            return XCTFail("Execute command must require approval")
        }
    }

    func testCleverHandoffRequiresApproval() {
        let decision = engine.authorize(
            CommandRequest(
                name: "clever.open",
                payload: ["prompt": "Plan my day", "url": "com.turbofasttools.geniusai://"]
            )
        )
        guard case .requireApproval = decision else {
            return XCTFail("Clever AI app handoff must require explicit approval")
        }
    }

    func testUnknownAndMissingPayloadCommandsAreDenied() {
        guard case .deny = engine.authorize(CommandRequest(name: "terminal.run", payload: [:])) else {
            return XCTFail("Unknown command must be denied")
        }
        guard case .deny = engine.authorize(CommandRequest(name: "shortcut.run", payload: [:])) else {
            return XCTFail("Missing payload must be denied")
        }
    }

    func testRegisteredCommandSerializationPreservesPermissionBoundary() {
        let read = CommandRequest(name: "system.status", payload: [:])
        let prepare = CommandRequest(name: "shortcut.prepare", payload: ["shortcutName": "System Online"])
        let execute = CommandRequest(name: "shortcut.run", payload: ["shortcutName": "System Online"])
        XCTAssertEqual(engine.authorize(read), .allow)
        XCTAssertEqual(engine.authorize(prepare), .allow)
        guard case .requireApproval = engine.authorize(execute) else {
            return XCTFail("Serialized shortcut.run must remain approval-gated")
        }
    }

    func testCleverAIHandoffUsesVerifiedUniversalLinkAndStoreFallback() {
        XCTAssertEqual(CleverAIHandoff.bundleIdentifier, "com.turbofasttools.geniusai")
        XCTAssertEqual(CleverAIHandoff.universalURL.host, "cleverai.app")
        XCTAssertEqual(CleverAIHandoff.universalURL.path, "/app")
        XCTAssertEqual(CleverAIHandoff.appStoreURL.scheme, "itms-apps")
        XCTAssertTrue(CleverAIHandoff.appStoreURL.absoluteString.contains("1667722375"))
    }

    func testAppleIntelligenceRouteIsExplicitlyLocal() {
        XCTAssertEqual(AgentRoute.apple.displayName, "Apple Intelligence")
        XCTAssertNotEqual(AgentRoute.apple, .openai)
        XCTAssertNotEqual(AgentRoute.apple, .openclaw)
    }

    func testApprovalExpiresAndCannotReplay() async throws {
        let store = ApprovalStore()
        let action = makeAction(expiresAt: Date().addingTimeInterval(60))
        try await store.register(action)
        try await store.consume(action)
        do {
            try await store.consume(action)
            XCTFail("Consumed approval must not replay")
        } catch {
            XCTAssertNotNil(error as? AgentError)
        }

        let expired = makeAction(expiresAt: Date().addingTimeInterval(-1))
        do {
            try await store.register(expired)
            XCTFail("Expired approval must be rejected")
        } catch {
            XCTAssertNotNil(error as? AgentError)
        }
    }

    func testRequestEncodingAndResponseDecoding() throws {
        let conversationID = UUID()
        let request = AgentRequest(
            conversationID: conversationID,
            route: .openclaw,
            message: "status",
            systemInstruction: "Be accurate."
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let requestData = try encoder.encode(request)
        let requestJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        XCTAssertEqual(requestJSON["conversation_id"] as? String, conversationID.uuidString)
        XCTAssertEqual(requestJSON["route"] as? String, "openclaw")

        let responseJSON: [String: Any] = [
            "request_id": UUID().uuidString,
            "conversation_id": conversationID.uuidString,
            "route": "openai",
            "agent": "CARINA",
            "provider": "openai",
            "model": "test-model",
            "text": "online",
            "status": "informational",
            "prepared_action": NSNull(),
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(AgentResponse.self, from: responseData)
        XCTAssertEqual(response.text, "online")
        XCTAssertEqual(response.route, .openai)
    }

    func testMockProviderReturnsInjectedResponse() async throws {
        let response = AgentResponse(
            requestId: UUID(),
            conversationId: UUID(),
            route: .openclaw,
            agent: "CARINA",
            provider: "mock",
            model: nil,
            text: "mock response",
            status: .informational,
            preparedAction: nil
        )
        let provider = MockAgentProvider(response: response)
        let request = AgentRequest(
            conversationID: response.conversationId,
            route: .openclaw,
            message: "hello",
            systemInstruction: "test"
        )
        let actualResponse = try await provider.send(request)
        XCTAssertEqual(actualResponse, response)
    }

    @MainActor
    func testCredentialManagerSaveLoadDeleteWithMockStore() async {
        let store = InMemoryCredentialStore()
        let manager = CredentialManager(store: store)
        manager.bridgeToken = String(repeating: "a", count: 40)
        let saved = await manager.save()
        XCTAssertTrue(saved)
        await manager.load()
        XCTAssertTrue(manager.hasBridgeToken)
        await manager.delete()
        XCTAssertFalse(manager.hasBridgeToken)
    }

    private func makeAction(expiresAt: Date) -> PreparedAction {
        let payload = ["shortcutName": "Test"]
        let request = CommandRequest(name: "shortcut.run", payload: payload)
        return PreparedAction(
            id: UUID(),
            command: request.name,
            summary: "Run Test",
            payload: payload,
            permission: .execute,
            fingerprint: CommandPermissionEngine.fingerprint(for: request),
            createdAt: Date(),
            expiresAt: expiresAt
        )
    }
}

private actor InMemoryCredentialStore: SecureCredentialStoring {
    private var values: [String: String] = [:]

    func save(_ value: String, account: String) {
        values[account] = value
    }

    func load(account: String) -> String? {
        values[account]
    }

    func delete(account: String) {
        values.removeValue(forKey: account)
    }
}
