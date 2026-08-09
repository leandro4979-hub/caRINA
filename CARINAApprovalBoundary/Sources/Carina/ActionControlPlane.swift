import CryptoKit
import Foundation

public enum ActionKind: String, Codable, Sendable { case read, draft, stage, commit, admin }
public enum ActionRisk: String, Codable, Sendable { case none, external, high, admin }
public enum LedgerState: String, Codable, Sendable { case planned, approved, denied, expired, dispatching, verified, failed, unknown }

/// A capability is compiled from a reviewed registry entry. LLM output never
/// creates one of these values at runtime.
public struct Capability: Codable, Sendable, Equatable {
    public let id: String
    public let versionMajor: Int
    public let allowedInputs: Set<String>
    public let maxRecipients: Int
    public let allowedAccounts: Set<String>
    public let kind: ActionKind
    public let risk: ActionRisk

    public init(id: String, versionMajor: Int = 1, allowedInputs: Set<String>, maxRecipients: Int = 0, allowedAccounts: Set<String> = [], kind: ActionKind, risk: ActionRisk) {
        self.id = id; self.versionMajor = versionMajor; self.allowedInputs = allowedInputs
        self.maxRecipients = maxRecipients; self.allowedAccounts = allowedAccounts
        self.kind = kind; self.risk = risk
    }
}

/// An immutable deployment snapshot. Key lookup is O(1) and version-specific.
public struct CapabilityRegistrySnapshot: Sendable {
    public let id: String
    private let allowlist: [CapabilityKey: Capability]

    public init(id: String, capabilities: [Capability]) {
        self.id = id
        self.allowlist = Dictionary(uniqueKeysWithValues: capabilities.map { (CapabilityKey(id: $0.id, versionMajor: $0.versionMajor), $0) })
    }

    public func capability(id: String, versionMajor: Int) -> Capability? {
        allowlist[CapabilityKey(id: id, versionMajor: versionMajor)]
    }
}

public struct CapabilityKey: Hashable, Sendable, Codable {
    public let id: String
    public let versionMajor: Int
    public init(id: String, versionMajor: Int) { self.id = id; self.versionMajor = versionMajor }
}

public enum CapabilityError: Error, Sendable, Equatable {
    case disabled, unknownCapability, unknownInput(String), recipientLimit, accountNotAllowed, invalidTransition, tamperedPlan
}

/// The only artifact which may cross the approval boundary. It contains the
/// reviewed registry identity and normalized parameters, never raw LLM text.
public struct ActionPlan: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID; public let correlationID: UUID; public let userID: String; public let deviceID: String
    public let registrySnapshotID: String; public let capabilityID: String; public let capabilityVersionMajor: Int
    public let target: String; public let normalizedPayload: [String: String]; public let payloadHash: String
    public let kind: ActionKind; public let risk: ActionRisk; public let requiredPermissions: [String]; public let preflight: [String: Bool]
    public let approvalNonce: UUID; public let expiresAt: Date; public let idempotencyKey: String; public let lockedArtifactHash: String

    fileprivate init(correlationID: UUID, userID: String, deviceID: String, snapshotID: String, capability: Capability, target: String, payload: [String: String], requiredPermissions: [String], preflight: [String: Bool], expiresAt: Date) {
        self.id = UUID(); self.correlationID = correlationID; self.userID = userID; self.deviceID = deviceID
        self.registrySnapshotID = snapshotID; self.capabilityID = capability.id; self.capabilityVersionMajor = capability.versionMajor; self.target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedPayload = payload.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        self.kind = capability.kind; self.risk = capability.risk; self.requiredPermissions = requiredPermissions.sorted(); self.preflight = preflight
        self.approvalNonce = UUID(); self.expiresAt = expiresAt
        self.payloadHash = Self.hash(Self.payloadMaterial(self.normalizedPayload))
        self.idempotencyKey = Self.hash("\(correlationID.uuidString.lowercased()):\(self.payloadHash)")
        self.lockedArtifactHash = Self.hash(Self.lockMaterial(
            id: self.id, correlationID: correlationID, userID: userID, deviceID: deviceID, snapshotID: snapshotID, capability: capability,
            target: self.target, payload: self.normalizedPayload, permissions: self.requiredPermissions, preflight: preflight,
            nonce: self.approvalNonce, expiresAt: expiresAt, idempotencyKey: self.idempotencyKey
        ))
    }

    public func isIntact() -> Bool {
        lockedArtifactHash == Self.hash(Self.lockMaterial(id: id, correlationID: correlationID, userID: userID, deviceID: deviceID, snapshotID: registrySnapshotID,
            capabilityID: capabilityID, versionMajor: capabilityVersionMajor, kind: kind, risk: risk, target: target, payload: normalizedPayload,
            permissions: requiredPermissions, preflight: preflight, nonce: approvalNonce, expiresAt: expiresAt, idempotencyKey: idempotencyKey))
    }

    private static func payloadMaterial(_ payload: [String: String]) -> String { payload.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\u{001F}") }
    private static func lockMaterial(id: UUID, correlationID: UUID, userID: String, deviceID: String, snapshotID: String, capability: Capability, target: String, payload: [String: String], permissions: [String], preflight: [String: Bool], nonce: UUID, expiresAt: Date, idempotencyKey: String) -> String {
        lockMaterial(id: id, correlationID: correlationID, userID: userID, deviceID: deviceID, snapshotID: snapshotID, capabilityID: capability.id, versionMajor: capability.versionMajor, kind: capability.kind, risk: capability.risk, target: target, payload: payload, permissions: permissions, preflight: preflight, nonce: nonce, expiresAt: expiresAt, idempotencyKey: idempotencyKey)
    }
    private static func lockMaterial(id: UUID, correlationID: UUID, userID: String, deviceID: String, snapshotID: String, capabilityID: String, versionMajor: Int, kind: ActionKind, risk: ActionRisk, target: String, payload: [String: String], permissions: [String], preflight: [String: Bool], nonce: UUID, expiresAt: Date, idempotencyKey: String) -> String {
        [id.uuidString.lowercased(), correlationID.uuidString.lowercased(), userID, deviceID, snapshotID, capabilityID, String(versionMajor), kind.rawValue, risk.rawValue, target, payloadMaterial(payload), permissions.sorted().joined(separator: ","), preflight.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"), nonce.uuidString.lowercased(), String(expiresAt.timeIntervalSince1970), idempotencyKey].joined(separator: "\u{001F}")
    }
    private static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}

public struct CapabilityFirewall: Sendable {
    private let snapshot: CapabilityRegistrySnapshot
    public init(snapshot: CapabilityRegistrySnapshot) { self.snapshot = snapshot }
    public init(capabilities: [Capability]) { self.init(snapshot: CapabilityRegistrySnapshot(id: "local", capabilities: capabilities)) }

    public func compile(correlationID: UUID, userID: String, deviceID: String, capabilityID: String, capabilityVersionMajor: Int = 1, target: String, payload: [String: String], requiredPermissions: [String], preflight: [String: Bool], expiresAt: Date) throws -> ActionPlan {
        guard let capability = snapshot.capability(id: capabilityID, versionMajor: capabilityVersionMajor) else { throw CapabilityError.unknownCapability }
        guard preflight.values.allSatisfy({ $0 }) else { throw CapabilityError.invalidTransition }
        for key in payload.keys where !capability.allowedInputs.contains(key) { throw CapabilityError.unknownInput(key) }
        if let recipients = payload["recipients"], recipients.split(separator: ",").count > capability.maxRecipients { throw CapabilityError.recipientLimit }
        if let account = payload["account"], !capability.allowedAccounts.isEmpty, !capability.allowedAccounts.contains(account) { throw CapabilityError.accountNotAllowed }
        return ActionPlan(correlationID: correlationID, userID: userID, deviceID: deviceID, snapshotID: snapshot.id, capability: capability, target: target, payload: payload, requiredPermissions: requiredPermissions, preflight: preflight, expiresAt: expiresAt)
    }
}

/// A metadata-only review artifact. Its consumer has no execution interface.
public enum FailedProposalReason: String, Codable, Sendable, Equatable { case unknownCapability, policyRejected }

public struct FailedCapabilityProposal: Codable, Sendable, Equatable {
    public let correlationID: UUID; public let tenantID: String; public let requestedCapabilityID: String
    public let requestedVersionMajor: Int; public let intentHash: String; public let suggestedSchemaHash: String; public let reason: FailedProposalReason
    public init(correlationID: UUID, tenantID: String, rawIntent: String, requestedCapabilityID: String, requestedVersionMajor: Int, suggestedSchemaJSON: String, reason: FailedProposalReason) {
        self.correlationID = correlationID; self.tenantID = tenantID; self.requestedCapabilityID = requestedCapabilityID; self.requestedVersionMajor = requestedVersionMajor
        self.intentHash = Self.hash(rawIntent); self.suggestedSchemaHash = Self.hash(suggestedSchemaJSON); self.reason = reason
    }
    private static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}

public enum BatchActionResult: Sendable, Equatable { case plan(ActionPlan), failed(FailedCapabilityProposal) }

public struct ActionBatchCompiler: Sendable {
    private let firewall: CapabilityFirewall
    private let maxBatchSize: Int; private let maxPayloadBytes: Int
    public init(firewall: CapabilityFirewall, maxBatchSize: Int = 100, maxPayloadBytes: Int = 16_384) {
        precondition(maxBatchSize > 0 && maxPayloadBytes > 0)
        self.firewall = firewall; self.maxBatchSize = maxBatchSize; self.maxPayloadBytes = maxPayloadBytes
    }
    public func compile(_ requests: [ActionProposal], expiresAt: Date) -> [BatchActionResult] {
        requests.enumerated().map { index, request in
            guard index < maxBatchSize, request.payloadSizeBytes <= maxPayloadBytes else {
                return .failed(FailedCapabilityProposal(correlationID: request.correlationID, tenantID: request.tenantID, rawIntent: request.rawIntent, requestedCapabilityID: request.capabilityID, requestedVersionMajor: request.capabilityVersionMajor, suggestedSchemaJSON: request.suggestedSchemaJSON, reason: .policyRejected))
            }
            do { return .plan(try firewall.compile(correlationID: request.correlationID, userID: request.userID, deviceID: request.deviceID, capabilityID: request.capabilityID, capabilityVersionMajor: request.capabilityVersionMajor, target: request.target, payload: request.payload, requiredPermissions: request.requiredPermissions, preflight: request.preflight, expiresAt: expiresAt)) }
            catch { return .failed(FailedCapabilityProposal(correlationID: request.correlationID, tenantID: request.tenantID, rawIntent: request.rawIntent, requestedCapabilityID: request.capabilityID, requestedVersionMajor: request.capabilityVersionMajor, suggestedSchemaJSON: request.suggestedSchemaJSON, reason: .unknownCapability)) }
        }
    }
}

public struct ActionProposal: Sendable, Equatable {
    public let correlationID: UUID; public let tenantID: String; public let userID: String; public let deviceID: String; public let rawIntent: String
    public let capabilityID: String; public let capabilityVersionMajor: Int; public let target: String; public let payload: [String: String]
    public let requiredPermissions: [String]; public let preflight: [String: Bool]; public let suggestedSchemaJSON: String
    public init(correlationID: UUID, tenantID: String, userID: String, deviceID: String, rawIntent: String, capabilityID: String, capabilityVersionMajor: Int = 1, target: String, payload: [String: String], requiredPermissions: [String], preflight: [String: Bool], suggestedSchemaJSON: String = "{}") { self.correlationID = correlationID; self.tenantID = tenantID; self.userID = userID; self.deviceID = deviceID; self.rawIntent = rawIntent; self.capabilityID = capabilityID; self.capabilityVersionMajor = capabilityVersionMajor; self.target = target; self.payload = payload; self.requiredPermissions = requiredPermissions; self.preflight = preflight; self.suggestedSchemaJSON = suggestedSchemaJSON }
    fileprivate var payloadSizeBytes: Int { payload.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count } }
}

public actor ActionLedger {
    private var states: [UUID: LedgerState] = [:]; private var keys: [String: UUID] = [:]
    public init() {}
    public func reserve(_ plan: ActionPlan, now: Date = Date()) throws -> LedgerState {
        guard plan.isIntact() else { throw CapabilityError.tamperedPlan }
        if let existing = keys[plan.idempotencyKey] { return states[existing] ?? .unknown }
        guard plan.kind == .commit || plan.kind == .admin, plan.expiresAt > now else { throw CapabilityError.invalidTransition }
        keys[plan.idempotencyKey] = plan.id; states[plan.id] = .approved; return .approved
    }
    public func dispatch(_ plan: ActionPlan, now: Date = Date()) throws {
        guard plan.isIntact(), plan.expiresAt > now, states[plan.id] == .approved else { throw CapabilityError.invalidTransition }
        states[plan.id] = .dispatching
    }
    public func finish(_ plan: ActionPlan, verified: Bool?) throws {
        guard plan.isIntact(), states[plan.id] == .dispatching else { throw CapabilityError.invalidTransition }
        states[plan.id] = verified == true ? .verified : verified == false ? .failed : .unknown
    }
    public func state(for plan: ActionPlan) -> LedgerState? { states[plan.id] }
}
