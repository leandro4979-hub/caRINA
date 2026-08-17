import Foundation

public enum SofaError: Error, Sendable, Equatable {
    case missingCredential(String)
    case invalidConfiguration(String)
    case invalidResponse
    case invalidSession
    case httpStatus(code: Int, message: String)
    case decoding(String)
    case encoding(String)
    case missingField(String)
    case invalidVoteValue(Int)
    case verificationFeedbackTooLong(Int)
    case replyTooLong(Int)
    case unsupportedAction(String)
}

extension SofaError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingCredential(name):
            return "Missing SOFA credential in \(name)."
        case let .invalidConfiguration(message):
            return "Invalid SOFA configuration: \(message)"
        case .invalidResponse:
            return "SOFA returned a non-HTTP or otherwise invalid response."
        case .invalidSession:
            return "The SOFA session is invalid or expired."
        case let .httpStatus(code, message):
            return "SOFA request failed with HTTP \(code): \(message)"
        case let .decoding(message):
            return "Could not decode the SOFA response: \(message)"
        case let .encoding(message):
            return "Could not encode the SOFA request: \(message)"
        case let .missingField(field):
            return "Missing required SOFA field: \(field)."
        case let .invalidVoteValue(value):
            return "SOFA vote value must be 1 or -1, got \(value)."
        case let .verificationFeedbackTooLong(count):
            return "SOFA verification feedback is limited to 500 characters, got \(count)."
        case let .replyTooLong(count):
            return "SOFA reply body is limited to 25,000 characters, got \(count)."
        case let .unsupportedAction(action):
            return "Unsupported SOFA action: \(action)."
        }
    }
}
