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
}
