import Foundation

public struct SofaContributionAdapter<Transport: SofaContributionTransport>: AppIntentAdapter, Sendable {
    public typealias Output = SofaMutationReceipt

    private let transport: Transport
    private let approvedRegistrySnapshotIDs: Set<String>

    public init(
        transport: Transport,
        approvedRegistrySnapshotIDs: Set<String> = [SofaCapabilityCatalog.snapshotID]
    ) {
        precondition(!approvedRegistrySnapshotIDs.isEmpty)
        self.transport = transport
        self.approvedRegistrySnapshotIDs = approvedRegistrySnapshotIDs
    }

    public static func target(postID: String) -> String {
        "sofa:\(postID)"
    }

    /// Serializes the one locked ActionPlan that is allowed to cross the
    /// existing approval boundary. The protected executor uses the plan's
    /// stable idempotency key and the approval fingerprint binds the encoded
    /// plan plus its human-visible target.
    public func commandRequest(for plan: ActionPlan, now: Date = Date()) throws -> CommandRequest {
        _ = try validate(plan: plan, requestTarget: plan.target, idempotencyKey: plan.idempotencyKey, now: now)
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(plan)
        } catch {
            throw SofaError.encoding(String(describing: error))
        }
        return CommandRequest(
            intentID: .sofaContribution,
            payload: [
                "actionPlan": encoded.base64EncodedString(),
                "idempotencyKey": plan.idempotencyKey
            ],
            target: plan.target
        )
    }

    public func execute(_ request: CommandRequest) async throws -> SofaMutationReceipt {
        guard request.intentID == .sofaContribution else {
            throw SofaError.unsupportedAction(request.intentID.rawValue)
        }
        guard Set(request.payload.keys) == ["actionPlan", "idempotencyKey"],
              let encodedPlan = request.payload["actionPlan"],
              let data = Data(base64Encoded: encodedPlan),
              let idempotencyKey = request.payload["idempotencyKey"] else {
            throw SofaError.invalidActionPlan
        }

        let plan: ActionPlan
        do {
            plan = try JSONDecoder().decode(ActionPlan.self, from: data)
        } catch {
            throw SofaError.invalidActionPlan
        }

        let capability = try validate(
            plan: plan,
            requestTarget: request.target,
            idempotencyKey: idempotencyKey,
            now: Date()
        )
        let payload = plan.normalizedPayload
        guard let postID = payload["postID"], !postID.isEmpty else {
            throw SofaError.missingField("postID")
        }

        switch capability.id {
        case SofaCapabilityCatalog.vote.id:
            guard let rawValue = payload["value"], let value = Int(rawValue) else {
                throw SofaError.missingField("value")
            }
            return try await transport.vote(postID: postID, value: value)

        case SofaCapabilityCatalog.verify.id:
            guard let rawOutcome = payload["outcome"],
                  let outcome = SofaVerificationOutcome(rawValue: rawOutcome) else {
                throw SofaError.missingField("outcome")
            }
            guard let feedback = payload["feedback"] else {
                throw SofaError.missingField("feedback")
            }
            return try await transport.verify(postID: postID, outcome: outcome, feedback: feedback)

        case SofaCapabilityCatalog.reply.id:
            guard let body = payload["body"], !body.isEmpty else {
                throw SofaError.missingField("body")
            }
            return try await transport.reply(postID: postID, body: body)

        default:
            throw SofaError.unsupportedCapability(capability.id)
        }
    }

    private func validate(
        plan: ActionPlan,
        requestTarget: String,
        idempotencyKey: String,
        now: Date
    ) throws -> Capability {
        guard plan.isIntact(), plan.expiresAt > now else {
            throw SofaError.invalidActionPlan
        }
        guard approvedRegistrySnapshotIDs.contains(plan.registrySnapshotID) else {
            throw SofaError.unapprovedRegistrySnapshot(plan.registrySnapshotID)
        }
        guard let capability = SofaCapabilityCatalog.mutationCapability(
            id: plan.capabilityID,
            versionMajor: plan.capabilityVersionMajor
        ) else {
            throw SofaError.unsupportedCapability(plan.capabilityID)
        }
        guard plan.kind == capability.kind,
              plan.risk == capability.risk,
              plan.kind == .commit,
              plan.risk == .external,
              plan.idempotencyKey == idempotencyKey,
              Set(plan.normalizedPayload.keys).isSubset(of: capability.allowedInputs),
              requestTarget == plan.target else {
            throw SofaError.invalidActionPlan
        }
        guard let postID = plan.normalizedPayload["postID"], !postID.isEmpty,
              plan.target == Self.target(postID: postID) else {
            throw SofaError.invalidActionPlan
        }
        return capability
    }
}
