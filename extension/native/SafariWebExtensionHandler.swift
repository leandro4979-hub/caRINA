import Foundation
import OSLog
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(subsystem: "carina.browser.automation", category: "NativeBridge")

    private static let hex32 = try! NSRegularExpression(pattern: "^[a-f0-9]{32}$")
    private static let candidateID = try! NSRegularExpression(pattern: "^[A-Za-z0-9._:-]{1,128}$")
    private static let pluginID = try! NSRegularExpression(pattern: "^[a-z0-9._-]{1,64}$")
    private static let allowedIntents: Set<String> = ["SkipInterruption", "ContinuePlayback", "CloseOverlay"]

    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo as? [String: Any],
            let message = userInfo[SFExtensionMessageKey] as? [String: Any]
        else {
            respondWithDefaultDeny(context: context, reason: "INVALID_MESSAGE_FORMAT")
            return
        }

        guard let request = validatePolicyRequest(message) else {
            respondWithDefaultDeny(context: context, reason: "MALFORMED_POLICY_REQUEST")
            return
        }

        logger.info("Processing Phase 1 policy request: \(request.requestID, privacy: .public)")

        let response: [String: Any] = [
            "type": "POLICY_RESULT",
            "version": 1,
            "requestId": request.requestID,
            "nonce": request.nonce,
            "candidateId": request.candidateID,
            "decision": "DENY",
            "reasonCode": "PHASE_1_DEFAULT_DENY"
        ]

        completeRequest(context: context, response: response)
    }

    private struct ValidatedPolicyRequest {
        let requestID: String
        let nonce: String
        let candidateID: String
    }

    private func validatePolicyRequest(_ message: [String: Any]) -> ValidatedPolicyRequest? {
        let expectedKeys: Set<String> = [
            "type", "version", "requestId", "nonce", "candidateId", "pluginId", "intent",
            "proposedAction", "tabId", "frameId", "origin", "host", "confidence", "observedAt", "receivedAt"
        ]

        guard Set(message.keys) == expectedKeys else { return nil }
        guard message["type"] as? String == "POLICY_REQUEST" else { return nil }
        guard let version = integer(message["version"]), version == 1 else { return nil }
        guard let requestID = message["requestId"] as? String, matches(Self.hex32, requestID) else { return nil }
        guard let nonce = message["nonce"] as? String, matches(Self.hex32, nonce) else { return nil }
        guard let candidateID = message["candidateId"] as? String, matches(Self.candidateID, candidateID) else { return nil }
        guard let pluginID = message["pluginId"] as? String, matches(Self.pluginID, pluginID) else { return nil }
        guard let intent = message["intent"] as? String, Self.allowedIntents.contains(intent) else { return nil }
        guard message["proposedAction"] as? String == "click" else { return nil }
        guard let tabID = integer(message["tabId"]), tabID >= 0 else { return nil }
        guard let frameID = integer(message["frameId"]), frameID >= 0 else { return nil }
        guard let origin = message["origin"] as? String, !origin.isEmpty, origin.utf8.count <= 512 else { return nil }
        guard let host = message["host"] as? String, !host.isEmpty, host.utf8.count <= 253 else { return nil }
        guard let confidence = number(message["confidence"]), (0.0...1.0).contains(confidence) else { return nil }
        guard let observedAt = integer(message["observedAt"]), observedAt >= 0 else { return nil }
        guard let receivedAt = integer(message["receivedAt"]), receivedAt >= 0 else { return nil }
        _ = pluginID
        _ = intent
        _ = tabID
        _ = frameID
        _ = origin
        _ = host
        _ = confidence
        _ = observedAt
        _ = receivedAt
        return ValidatedPolicyRequest(requestID: requestID, nonce: nonce, candidateID: candidateID)
    }

    private func respondWithDefaultDeny(context: NSExtensionContext, reason: String) {
        logger.error("Native bridge rejected request: \(reason, privacy: .public)")
        completeRequest(context: context, response: [
            "type": "POLICY_RESULT",
            "version": 1,
            "requestId": "00000000000000000000000000000000",
            "nonce": "00000000000000000000000000000000",
            "candidateId": "unknown",
            "decision": "DENY",
            "reasonCode": reason
        ])
    }

    private func completeRequest(context: NSExtensionContext, response: [String: Any]) {
        let responseItem = NSExtensionItem()
        responseItem.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }

    private func matches(_ expression: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range)?.range == range
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double, double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    private func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
}
