import Foundation

public enum SofaCapabilityCatalog {
    public static let snapshotID = "carina-sofa-v1"

    public static let search = Capability(
        id: "sofa.search",
        allowedInputs: ["query", "perPage"],
        kind: .read,
        risk: .none
    )

    public static let getPost = Capability(
        id: "sofa.getPost",
        allowedInputs: ["postID"],
        kind: .read,
        risk: .none
    )

    public static let vote = Capability(
        id: "sofa.vote",
        allowedInputs: ["postID", "value"],
        kind: .commit,
        risk: .external
    )

    public static let verify = Capability(
        id: "sofa.verify",
        allowedInputs: ["postID", "outcome", "feedback"],
        kind: .commit,
        risk: .external
    )

    public static let reply = Capability(
        id: "sofa.reply",
        allowedInputs: ["postID", "body"],
        kind: .commit,
        risk: .external
    )

    public static let all: [Capability] = [search, getPost, vote, verify, reply]

    public static var snapshot: CapabilityRegistrySnapshot {
        CapabilityRegistrySnapshot(id: snapshotID, capabilities: all)
    }

    public static func mutationCapability(id: String, versionMajor: Int) -> Capability? {
        guard versionMajor == 1 else { return nil }
        switch id {
        case vote.id: return vote
        case verify.id: return verify
        case reply.id: return reply
        default: return nil
        }
    }
}
