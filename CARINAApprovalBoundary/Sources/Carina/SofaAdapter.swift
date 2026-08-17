import Foundation

public struct SofaContributionAdapter<Transport: SofaContributionTransport>: AppIntentAdapter, Sendable {
    public typealias Output = SofaMutationReceipt

    private let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    public static func target(postID: String) -> String {
        "sofa:\(postID)"
    }

    public func execute(_ request: CommandRequest) async throws -> SofaMutationReceipt {
        guard request.intentID == .sofaContribution else {
            throw SofaError.unsupportedAction(request.intentID.rawValue)
        }
        guard let action = request.payload["action"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !action.isEmpty else {
            throw SofaError.missingField("action")
        }
        guard let postID = request.payload["postID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !postID.isEmpty else {
            throw SofaError.missingField("postID")
        }
        guard request.target == Self.target(postID: postID) else {
            throw SofaError.invalidConfiguration("approval target must exactly match \(Self.target(postID: postID))")
        }

        switch action {
        case "vote":
            guard let rawValue = request.payload["value"], let value = Int(rawValue) else {
                throw SofaError.missingField("value")
            }
            return try await transport.vote(postID: postID, value: value)

        case "verify":
            guard let rawOutcome = request.payload["outcome"],
                  let outcome = SofaVerificationOutcome(rawValue: rawOutcome) else {
                throw SofaError.missingField("outcome")
            }
            let feedback = request.payload["feedback"] ?? ""
            return try await transport.verify(postID: postID, outcome: outcome, feedback: feedback)

        case "reply":
            guard let body = request.payload["body"], !body.isEmpty else {
                throw SofaError.missingField("body")
            }
            return try await transport.reply(postID: postID, body: body)

        default:
            throw SofaError.unsupportedAction(action)
        }
    }
}
