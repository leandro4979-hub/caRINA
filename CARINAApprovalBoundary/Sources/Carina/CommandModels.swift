import Foundation

public enum CommandIntentID: String, Codable, Sendable {
    case systemStatus
    case workspaceSync
}

public enum CommandSource: String, Codable, Sendable {
    case userInterface
    case bridge
}

public struct CommandRequest: Codable, Sendable, Equatable {
    public let intentID: CommandIntentID
    public let payload: [String: String]

    public init(intentID: CommandIntentID, payload: [String: String]) {
        self.intentID = intentID
        self.payload = payload
    }
}

public struct CommandEnvelope: Codable, Sendable, Equatable {
    public let version: UInt
    public let requestID: UUID
    public let sessionID: UUID
    public let sequence: UInt64
    public let nonce: UUID
    public let source: CommandSource
    public let request: CommandRequest

    public init(
        version: UInt,
        requestID: UUID,
        sessionID: UUID,
        sequence: UInt64,
        nonce: UUID,
        source: CommandSource,
        request: CommandRequest
    ) {
        self.version = version
        self.requestID = requestID
        self.sessionID = sessionID
        self.sequence = sequence
        self.nonce = nonce
        self.source = source
        self.request = request
    }
}
