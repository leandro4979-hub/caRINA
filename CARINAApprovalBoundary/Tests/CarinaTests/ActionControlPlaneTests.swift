import XCTest
@testable import Carina

final class ActionControlPlaneTests: XCTestCase {
    private let capability = Capability(id: "send_work_brief", allowedInputs: ["recipients", "account", "subject"], maxRecipients: 1, allowedAccounts: ["work"], kind: .commit, risk: .external)

    func testFirewallCompilesNormalizedPlanWithStableIdempotencyKey() throws {
        let firewall = CapabilityFirewall(capabilities: [capability])
        let plan = try firewall.compile(correlationID: UUID(), userID: "u", deviceID: "d", capabilityID: "send_work_brief", target: "alex@company.com", payload: ["recipients": "alex@company.com", "account": "work", "subject": " Brief "], requiredPermissions: ["mail"], preflight: ["bridge": true, "mail": true], expiresAt: Date().addingTimeInterval(60))
        XCTAssertEqual(plan.normalizedPayload["subject"], "Brief")
        XCTAssertEqual(plan.kind, .commit)
        XCTAssertFalse(plan.idempotencyKey.isEmpty)
    }

    func testFirewallRejectsParameterSmugglingAndTargetPreflightFailure() {
        let firewall = CapabilityFirewall(capabilities: [capability])
        XCTAssertThrowsError(try firewall.compile(correlationID: UUID(), userID: "u", deviceID: "d", capabilityID: "send_work_brief", target: "alex", payload: ["bcc": "hidden"], requiredPermissions: [], preflight: ["bridge": true], expiresAt: Date().addingTimeInterval(60)))
        XCTAssertThrowsError(try firewall.compile(correlationID: UUID(), userID: "u", deviceID: "d", capabilityID: "send_work_brief", target: "alex", payload: [:], requiredPermissions: [], preflight: ["bridge": false], expiresAt: Date().addingTimeInterval(60)))
    }

    func testLedgerSuppressesDuplicateAndRequiresVerification() async throws {
        let plan = try CapabilityFirewall(capabilities: [capability]).compile(correlationID: UUID(), userID: "u", deviceID: "d", capabilityID: "send_work_brief", target: "alex", payload: ["recipients": "alex", "account": "work"], requiredPermissions: [], preflight: ["bridge": true], expiresAt: Date().addingTimeInterval(60))
        let ledger = ActionLedger()
        let firstReservation = try await ledger.reserve(plan)
        let duplicateReservation = try await ledger.reserve(plan)
        XCTAssertEqual(firstReservation, .approved)
        XCTAssertEqual(duplicateReservation, .approved)
        try await ledger.dispatch(plan)
        try await ledger.finish(plan, verified: nil)
        let state = await ledger.state(for: plan)
        XCTAssertEqual(state, .unknown)
    }

    func testVersionMismatchFailsBeforePayloadValidation() {
        let snapshot = CapabilityRegistrySnapshot(id: "snapshot-7", capabilities: [capability])
        let firewall = CapabilityFirewall(snapshot: snapshot)
        XCTAssertThrowsError(try firewall.compile(
            correlationID: UUID(), userID: "u", deviceID: "d", capabilityID: "send_work_brief", capabilityVersionMajor: 2,
            target: "alex", payload: ["not-an-allowed-field": "x"], requiredPermissions: [], preflight: [:], expiresAt: Date().addingTimeInterval(60)
        )) { error in
            XCTAssertEqual(error as? CapabilityError, .unknownCapability)
        }
    }

    func testBatchKeepsValidPlanWhenAnotherCapabilityIsUnknown() throws {
        let firewall = CapabilityFirewall(snapshot: CapabilityRegistrySnapshot(id: "snapshot-9", capabilities: [capability]))
        let valid = ActionProposal(correlationID: UUID(), tenantID: "tenant", userID: "u", deviceID: "d", rawIntent: "email Alex", capabilityID: "send_work_brief", target: "alex", payload: ["recipients": "alex", "account": "work"], requiredPermissions: [], preflight: ["bridge": true])
        let unknown = ActionProposal(correlationID: UUID(), tenantID: "tenant", userID: "u", deviceID: "d", rawIntent: "invent a thing", capabilityID: "made_up", target: "x", payload: [:], requiredPermissions: [], preflight: [:], suggestedSchemaJSON: #"{\"fields\":[\"x\"]}"#)

        let results = ActionBatchCompiler(firewall: firewall).compile([valid, unknown], expiresAt: Date().addingTimeInterval(60))
        guard case .plan(let plan) = results[0] else { return XCTFail("expected approved capability") }
        XCTAssertEqual(plan.registrySnapshotID, "snapshot-9")
        guard case .failed(let stub) = results[1] else { return XCTFail("expected DLQ stub") }
        XCTAssertEqual(stub.requestedCapabilityID, "made_up")
        XCTAssertEqual(stub.reason, .unknownCapability)
        XCTAssertNotEqual(stub.intentHash, "invent a thing")
        XCTAssertFalse(String(data: try JSONEncoder().encode(stub), encoding: .utf8)!.contains("invent a thing"))
    }

    func testLedgerRejectsPlanWhoseLockedArtifactHashDoesNotMatch() async throws {
        let plan = try CapabilityFirewall(capabilities: [capability]).compile(correlationID: UUID(), userID: "u", deviceID: "d", capabilityID: "send_work_brief", target: "alex", payload: ["recipients": "alex", "account": "work"], requiredPermissions: [], preflight: ["bridge": true], expiresAt: Date().addingTimeInterval(60))
        let encoded = try JSONEncoder().encode(plan)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object["target"] = "mallory"
        let tampered = try JSONDecoder().decode(ActionPlan.self, from: JSONSerialization.data(withJSONObject: object))
        await XCTAssertThrowsErrorAsync(try await ActionLedger().reserve(tampered)) { error in
            XCTAssertEqual(error as? CapabilityError, .tamperedPlan)
        }
    }

    func testLedgerRejectsRepeatCompletion() async throws {
        let plan = try CapabilityFirewall(capabilities: [capability]).compile(correlationID: UUID(), userID: "u", deviceID: "d", capabilityID: "send_work_brief", target: "alex", payload: ["recipients": "alex", "account": "work"], requiredPermissions: [], preflight: ["bridge": true], expiresAt: Date().addingTimeInterval(60))
        let ledger = ActionLedger()
        _ = try await ledger.reserve(plan)
        try await ledger.dispatch(plan)
        try await ledger.finish(plan, verified: true)
        await XCTAssertThrowsErrorAsync(try await ledger.finish(plan, verified: true)) { error in
            XCTAssertEqual(error as? CapabilityError, .invalidTransition)
        }
    }

    func testOversizePayloadBecomesPrivacyMinimizedPolicyStub() throws {
        let request = ActionProposal(correlationID: UUID(), tenantID: "tenant", userID: "u", deviceID: "d", rawIntent: "super secret action", capabilityID: "send_work_brief", target: "alex", payload: ["subject": String(repeating: "x", count: 20)], requiredPermissions: [], preflight: [:])
        let compiler = ActionBatchCompiler(firewall: CapabilityFirewall(capabilities: [capability]), maxPayloadBytes: 8)
        let results = compiler.compile([request], expiresAt: Date().addingTimeInterval(60))
        guard case .failed(let stub) = results[0] else { return XCTFail("expected policy stub") }
        XCTAssertEqual(stub.reason, .policyRejected)
        XCTAssertFalse(String(data: try JSONEncoder().encode(stub), encoding: .utf8)!.contains("super secret action"))
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, _ handler: (Error) -> Void) async {
    do { _ = try await expression(); XCTFail("expected error") } catch { handler(error) }
}
