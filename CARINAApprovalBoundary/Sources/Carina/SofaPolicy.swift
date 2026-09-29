import Foundation

public enum SofaOperation: Sendable, Equatable {
    case search
    case getPost
    case vote
    case verify
    case reply
}

public enum SofaPolicy {
    public static func permission(for operation: SofaOperation) -> CommandPermission {
        switch operation {
        case .search, .getPost:
            return .read
        case .vote, .verify, .reply:
            return .execute
        }
    }

    /// Execution permission is derived from the registry-locked plan rather
    /// than caller-supplied action text.
    public static func permission(for plan: ActionPlan) -> CommandPermission {
        switch plan.kind {
        case .read:
            return .read
        case .draft, .stage:
            return .prepare
        case .commit, .admin:
            return .execute
        }
    }
}
