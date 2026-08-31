import Foundation

/// A Workspace scopes context, sources, skills, and sessions. It is deliberately
/// incapable of granting execution authority; capability policy remains owned by
/// CARINA's existing approval boundary.
public struct WorkspaceDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let sources: Set<String>
    public let skills: Set<String>
    public let sessionIsolation: Bool

    public init(
        id: String,
        name: String,
        sources: Set<String>,
        skills: Set<String>,
        sessionIsolation: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sources = sources
        self.skills = skills
        self.sessionIsolation = sessionIsolation
    }
}

public enum WorkspaceRoutingError: Error, Sendable, Equatable {
    case duplicateWorkspace(String)
    case unknownWorkspace(String)
    case unknownSkill(String)
    case sourceNotAllowed(String)
    case crossWorkspaceRequiresPolicy(origin: String, target: String)
    case sessionIsolationRequired(String)
}

/// Immutable deployment snapshot for Workspace routing.
public struct WorkspaceRegistrySnapshot: Sendable {
    public let id: String
    private let registry: [String: WorkspaceDefinition]

    public init(id: String, workspaces: [WorkspaceDefinition]) throws {
        var registry: [String: WorkspaceDefinition] = [:]
        for workspace in workspaces {
            guard registry[workspace.id] == nil else {
                throw WorkspaceRoutingError.duplicateWorkspace(workspace.id)
            }
            registry[workspace.id] = workspace
        }
        self.id = id
        self.registry = registry
    }

    public func workspace(id: String) -> WorkspaceDefinition? {
        registry[id]
    }

    public var workspaces: [WorkspaceDefinition] {
        registry.values.sorted { $0.id < $1.id }
    }
}

/// Metadata-only route request. It carries no model prompt, credential,
/// approval token, ActionPlan, or permission override.
public struct WorkspaceRouteRequest: Sendable, Equatable {
    public let originWorkspaceID: String
    public let targetWorkspaceID: String
    public let skillID: String
    public let sourceIDs: Set<String>

    public init(
        originWorkspaceID: String,
        targetWorkspaceID: String? = nil,
        skillID: String,
        sourceIDs: Set<String> = []
    ) {
        self.originWorkspaceID = originWorkspaceID
        self.targetWorkspaceID = targetWorkspaceID ?? originWorkspaceID
        self.skillID = skillID
        self.sourceIDs = sourceIDs
    }
}

/// A resolved Workspace route is still not authorization to execute. Callers
/// must continue through the CapabilityFirewall / approval runtime for actions.
public struct WorkspaceRoute: Sendable, Equatable {
    public let registrySnapshotID: String
    public let workspaceID: String
    public let skillID: String
    public let sourceIDs: Set<String>
    public let sessionIsolation: Bool
}

public struct WorkspaceRouter: Sendable {
    private let snapshot: WorkspaceRegistrySnapshot

    public init(snapshot: WorkspaceRegistrySnapshot) {
        self.snapshot = snapshot
    }

    public func route(_ request: WorkspaceRouteRequest) throws -> WorkspaceRoute {
        guard snapshot.workspace(id: request.originWorkspaceID) != nil else {
            throw WorkspaceRoutingError.unknownWorkspace(request.originWorkspaceID)
        }
        guard let target = snapshot.workspace(id: request.targetWorkspaceID) else {
            throw WorkspaceRoutingError.unknownWorkspace(request.targetWorkspaceID)
        }

        // WS-001 intentionally fails closed for cross-workspace requests. A
        // later policy integration may enable these only through CARINA's
        // existing authorization boundary.
        guard request.originWorkspaceID == request.targetWorkspaceID else {
            throw WorkspaceRoutingError.crossWorkspaceRequiresPolicy(
                origin: request.originWorkspaceID,
                target: request.targetWorkspaceID
            )
        }
        guard target.sessionIsolation else {
            throw WorkspaceRoutingError.sessionIsolationRequired(target.id)
        }
        guard target.skills.contains(request.skillID) else {
            throw WorkspaceRoutingError.unknownSkill(request.skillID)
        }
        for sourceID in request.sourceIDs where !target.sources.contains(sourceID) {
            throw WorkspaceRoutingError.sourceNotAllowed(sourceID)
        }

        return WorkspaceRoute(
            registrySnapshotID: snapshot.id,
            workspaceID: target.id,
            skillID: request.skillID,
            sourceIDs: request.sourceIDs,
            sessionIsolation: true
        )
    }
}

public enum CarinaWorkspaceCatalog {
    public static let engineering = WorkspaceDefinition(
        id: "engineering",
        name: "Engineering",
        sources: ["github", "codex", "local_repos"],
        skills: ["review_pr", "diagnose_ci", "dispatch_issue"]
    )

    public static let apple = WorkspaceDefinition(
        id: "apple",
        name: "Apple",
        sources: ["siri", "shortcuts", "xcode"],
        skills: ["build_shortcut", "deploy_iphone_app"]
    )

    public static let personal = WorkspaceDefinition(
        id: "personal",
        name: "Personal",
        sources: ["calendar", "documents"],
        skills: ["personal_automation"]
    )

    public static let v1: WorkspaceRegistrySnapshot = {
        // These definitions are compile-time reviewed constants. A duplicate ID
        // is a programmer/configuration error and must never produce a partial
        // registry.
        do {
            return try WorkspaceRegistrySnapshot(
                id: "carina-workspaces-v1",
                workspaces: [engineering, apple, personal]
            )
        } catch {
            preconditionFailure("Invalid built-in CARINA Workspace catalog: \(error)")
        }
    }()
}
