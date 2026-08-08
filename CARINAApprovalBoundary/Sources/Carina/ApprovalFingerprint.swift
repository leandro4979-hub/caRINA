import CryptoKit
import Foundation

public enum ApprovalFingerprint {
    public static func make(for envelope: CommandEnvelope) -> String {
        let canonicalPayload = envelope.request.payload
            .sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")

        let material = [
            String(envelope.version),
            envelope.requestID.uuidString.lowercased(),
            envelope.sessionID.uuidString.lowercased(),
            String(envelope.sequence),
            envelope.nonce.uuidString.lowercased(),
            envelope.source.rawValue,
            envelope.request.intentID.rawValue,
            canonicalPayload
        ].joined(separator: "\u{001F}")

        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func escape(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }
}
