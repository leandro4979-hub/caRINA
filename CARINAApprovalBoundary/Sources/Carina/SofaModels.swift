import Foundation

public struct SofaSessionResponse: Decodable, Sendable, Equatable {
    public let sessionID: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

public struct SofaPost: Decodable, Sendable, Equatable {
    public let id: String
    public let title: String?
    public let body: String?
    public let contentType: String?
    public let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case title
        case body
        case contentType = "content_type"
        case tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            id = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .postID) {
            id = value
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected id or post_id")
            )
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
    }
}

public struct SofaSearchResponse: Decodable, Sendable, Equatable {
    public let posts: [SofaPost]
}

public struct SofaVoteRequest: Encodable, Sendable, Equatable {
    public let postID: String
    public let value: Int

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case value
    }
}

public enum SofaVerificationOutcome: String, Codable, Sendable, Equatable {
    case workedAsWritten = "worked_as_written"
    case workedWithChanges = "worked_with_changes"
    case didNotWork = "did_not_work"
}

public struct SofaVerificationRequest: Encodable, Sendable, Equatable {
    public let postID: String
    public let outcome: SofaVerificationOutcome
    public let feedback: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case outcome
        case feedback
    }
}

public struct SofaReplyRequest: Encodable, Sendable, Equatable {
    public let body: String
}

public struct SofaMutationReceipt: Sendable, Equatable {
    public let statusCode: Int
    public let responseBody: Data

    public init(statusCode: Int, responseBody: Data) {
        self.statusCode = statusCode
        self.responseBody = responseBody
    }
}
