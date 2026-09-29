import Foundation
import SafariServices

/// The only native entry point through which Phase 2 execution authorization may
/// cross into the Safari Web Extension runtime.
///
/// The handler does not accept an authorization object from JavaScript. JavaScript
/// may request a previously staged authorization by ID; the native boundary
/// validates context, lifetime, fingerprint, single-use state, and CARINA's
/// authority binding before returning the authorization.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let boundary: SafariAuthorizationBoundary
    private let clock: @Sendable () -> Int

    init(
        boundary: SafariAuthorizationBoundary = SafariAuthorizationBoundary(),
        clock: @escaping @Sendable () -> Int = {
            Int(Date().timeIntervalSince1970 * 1000)
        }
    ) {
        self.boundary = boundary
        self.clock = clock
        super.init()
    }

    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo,
            let message = userInfo[SFExtensionMessageKey] as? [String: Any]
        else {
            reply(context: context, response: ["type": "AUTHORIZATION_DENIED", "reasonCode": "MALFORMED_MESSAGE"])
            return
        }

        guard message["type"] as? String == "EXECUTION_AUTHORIZATION_REQUEST" else {
            reply(context: context, response: ["type": "AUTHORIZATION_DENIED", "reasonCode": "UNSUPPORTED_MESSAGE"])
            return
        }

        guard
            let authorizationId = message["authorizationId"] as? String,
            let tabId = message["tabId"] as? Int,
            let frameId = message["frameId"] as? Int,
            let origin = message["origin"] as? String,
            tabId >= 0,
            frameId >= 0,
            origin.range(of: #"^https://[^/]+$"#, options: .regularExpression) != nil
        else {
            reply(context: context, response: ["type": "AUTHORIZATION_DENIED", "reasonCode": "INVALID_REQUEST"])
            return
        }

        let boundary = self.boundary
        let now = clock()
        let executionContext = SafariExecutionContext(
            tabId: tabId,
            frameId: frameId,
            origin: origin
        )

        Task {
            do {
                let authorization = try await boundary.consume(
                    authorizationId: authorizationId,
                    context: executionContext,
                    now: now
                )

                reply(context: context, response: [
                    "type": "EXECUTION_AUTHORIZATION",
                    "authorization": authorization.dictionaryRepresentation,
                ])
            } catch let error as AuthorizationBoundaryError {
                reply(context: context, response: [
                    "type": "AUTHORIZATION_DENIED",
                    "reasonCode": error.reasonCode,
                ])
            } catch {
                reply(context: context, response: [
                    "type": "AUTHORIZATION_DENIED",
                    "reasonCode": "BOUNDARY_FAILURE",
                ])
            }
        }
    }

    private func reply(context: NSExtensionContext, response: [String: Any]) {
        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}

private extension AuthorizationBoundaryError {
    var reasonCode: String {
        switch self {
        case .malformedMessage: return "MALFORMED_MESSAGE"
        case .unsupportedMessage: return "UNSUPPORTED_MESSAGE"
        case .invalidAuthorization: return "INVALID_AUTHORIZATION"
        case .expiredAuthorization: return "EXPIRED_AUTHORIZATION"
        case .contextMismatch: return "CONTEXT_MISMATCH"
        case .fingerprintMismatch: return "FINGERPRINT_MISMATCH"
        case .authorityBindingRejected: return "AUTHORITY_BINDING_REJECTED"
        case .authorizationAlreadyConsumed: return "AUTHORIZATION_ALREADY_CONSUMED"
        case .authorizationNotAvailable: return "AUTHORIZATION_NOT_AVAILABLE"
        }
    }
}

private extension ExecutionAuthorization {
    var dictionaryRepresentation: [String: Any] {
        [
            "type": type,
            "version": version,
            "authorizationId": authorizationId,
            "requestId": requestId,
            "nonce": nonce,
            "candidateId": candidateId,
            "pluginId": pluginId,
            "intent": intent,
            "action": action,
            "tabId": tabId,
            "frameId": frameId,
            "origin": origin,
            "issuedAt": issuedAt,
            "expiresAt": expiresAt,
            "executionFingerprint": executionFingerprint,
            "authorityBinding": authorityBinding,
        ]
    }
}
