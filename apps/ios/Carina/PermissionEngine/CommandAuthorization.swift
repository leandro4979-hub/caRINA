import CryptoKit
import Foundation

enum CarinaPermission: String, Codable, Sendable {
    case read
    case prepare
    case execute
}

enum AuthorizationDecision: Equatable, Sendable {
    case allow
    case requireApproval(reason: String)
    case deny(reason: String)
}

struct CommandDefinition: Equatable, Sendable {
    let name: String
    let permission: CarinaPermission
    let requiredPayloadKeys: Set<String>
}

struct CommandRequest: Equatable, Sendable {
    let name: String
    let payload: [String: String]
}

struct CommandPermissionEngine: Sendable {
    private let registry: [String: CommandDefinition]

    init() {
        let commands = [
            CommandDefinition(name: "system.status", permission: .read, requiredPayloadKeys: []),
            CommandDefinition(name: "agent.status", permission: .read, requiredPayloadKeys: ["agent"]),
            CommandDefinition(name: "bridge.status", permission: .read, requiredPayloadKeys: []),
            CommandDefinition(name: "openclaw.status", permission: .read, requiredPayloadKeys: []),
            CommandDefinition(name: "agent.message", permission: .read, requiredPayloadKeys: ["message"]),
            CommandDefinition(name: "shortcut.prepare", permission: .prepare, requiredPayloadKeys: ["shortcutName"]),
            CommandDefinition(name: "shortcut.run", permission: .execute, requiredPayloadKeys: ["shortcutName"]),
            CommandDefinition(name: "clever.open", permission: .execute, requiredPayloadKeys: ["prompt", "url"]),
        ]
        registry = Dictionary(uniqueKeysWithValues: commands.map { ($0.name, $0) })
    }

    func authorize(_ request: CommandRequest) -> AuthorizationDecision {
        guard let definition = registry[request.name] else {
            return .deny(reason: "Unsupported command: \(request.name)")
        }
        let missing = definition.requiredPayloadKeys.filter {
            request.payload[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
        guard missing.isEmpty else {
            return .deny(reason: "Missing required payload: \(missing.sorted().joined(separator: ", "))")
        }
        switch definition.permission {
        case .read, .prepare:
            return .allow
        case .execute:
            return .requireApproval(reason: "This action creates an external side effect and requires approval.")
        }
    }

    func validate(_ action: PreparedAction) -> AuthorizationDecision {
        let request = CommandRequest(name: action.command, payload: action.payload)
        let decision = authorize(request)
        guard action.fingerprint == Self.fingerprint(for: request) else {
            return .deny(reason: "The action payload does not match its security fingerprint.")
        }
        return decision
    }

    static func fingerprint(for request: CommandRequest) -> String {
        var canonical = request.name
        for key in request.payload.keys.sorted() {
            canonical += "\n\(key)=\(request.payload[key] ?? "")"
        }
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

actor ApprovalStore {
    private var pending: [UUID: PreparedAction] = [:]
    private var consumed: Set<UUID> = []

    func register(_ action: PreparedAction, now: Date = Date()) throws {
        guard action.expiresAt > now else {
            throw AgentError.approval("This approval request has expired.")
        }
        guard !consumed.contains(action.id), pending[action.id] == nil else {
            throw AgentError.approval("This approval request was already registered or consumed.")
        }
        pending[action.id] = action
    }

    func consume(_ action: PreparedAction, now: Date = Date()) throws {
        guard !consumed.contains(action.id) else {
            throw AgentError.approval("This approval was already consumed.")
        }
        guard let stored = pending[action.id] else {
            throw AgentError.approval("The approval request is no longer available.")
        }
        guard stored == action else {
            throw AgentError.approval("The approved action was modified.")
        }
        guard action.expiresAt > now else {
            pending.removeValue(forKey: action.id)
            throw AgentError.approval("This approval request has expired.")
        }
        pending.removeValue(forKey: action.id)
        consumed.insert(action.id)
    }

    func deny(_ action: PreparedAction) {
        pending.removeValue(forKey: action.id)
        consumed.insert(action.id)
    }
}
