import CryptoKit
import Foundation

public enum ActionReceiptStatus: String, Codable, Sendable, Equatable {
    case prepared, denied, approved, expired, cancelled
    case failedBeforeExecution = "failed-before-execution"
    case executionStarted = "execution-started"
    case executionSucceeded = "execution-succeeded"
    case executionFailed = "execution-failed"
}

/// Privacy-minimized receipt: no raw command payload, voice audio, credentials, or model output.
public struct ActionReceipt: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let correlationID: UUID
    public let fingerprint: String
    public let target: String
    public let status: ActionReceiptStatus
    public let createdAt: Date
    public let previousHash: String?
    public let eventHash: String
}

/// Append-only JSON-lines journal. Each event commits to the preceding hash so altered history fails verification.
public actor ActionActivityJournal {
    private var receipts: [ActionReceipt] = []
    private let fileURL: URL?

    public init(fileURL: URL? = nil) throws {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            receipts.append(try JSONDecoder().decode(ActionReceipt.self, from: Data(line.utf8)))
        }
        guard Self.isValid(receipts) else { throw JournalError.integrityFailure }
    }

    public func record(challenge: ApprovalChallenge, status: ActionReceiptStatus, now: Date = Date()) throws {
        try appendReceipt(
            correlationID: challenge.correlationID,
            fingerprint: challenge.fingerprint,
            target: challenge.target,
            status: status,
            now: now
        )
    }

    public func record(envelope: CommandEnvelope, status: ActionReceiptStatus, now: Date = Date()) throws {
        try appendReceipt(
            correlationID: envelope.requestID,
            fingerprint: ApprovalFingerprint.make(for: envelope),
            target: envelope.request.target,
            status: status,
            now: now
        )
    }

    public func recent(limit: Int = 10) -> [ActionReceipt] { Array(receipts.suffix(max(0, limit)).reversed()) }
    public func count(status: ActionReceiptStatus) -> Int { receipts.filter { $0.status == status }.count }
    public func integrityIsValid() -> Bool { Self.isValid(receipts) }

    private func appendReceipt(
        correlationID: UUID,
        fingerprint: String,
        target: String,
        status: ActionReceiptStatus,
        now: Date
    ) throws {
        let previousHash = receipts.last?.eventHash
        let receipt = ActionReceipt(
            id: UUID(), correlationID: correlationID, fingerprint: fingerprint,
            target: target, status: status, createdAt: now,
            previousHash: previousHash,
            eventHash: Self.hash(correlationID, fingerprint, target, status, now, previousHash)
        )
        receipts.append(receipt)
        if let fileURL { try Self.append(receipt, to: fileURL) }
    }

    private static func append(_ receipt: ActionReceipt, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(receipt) + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url); try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
        } else { try data.write(to: url, options: .atomic) }
    }
    private static func hash(_ id: UUID, _ fingerprint: String, _ target: String, _ status: ActionReceiptStatus, _ created: Date, _ previous: String?) -> String {
        let value = [id.uuidString, fingerprint, target, status.rawValue, String(created.timeIntervalSince1970), previous ?? ""].joined(separator: "\u{001F}")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func isValid(_ receipts: [ActionReceipt]) -> Bool {
        var previous: String?
        for receipt in receipts {
            guard receipt.previousHash == previous,
                  receipt.eventHash == hash(receipt.correlationID, receipt.fingerprint, receipt.target, receipt.status, receipt.createdAt, previous) else { return false }
            previous = receipt.eventHash
        }
        return true
    }
}

public enum JournalError: Error, Sendable, Equatable { case integrityFailure }

public struct TrustDashboard: Sendable, Equatable {
    public let privateModeEnabled: Bool
    public let bridgeState: String
    public let permissionIssues: [String]
    public let recentReceipts: [ActionReceipt]

    public init(privateModeEnabled: Bool, bridgeState: String, permissionIssues: [String], recentReceipts: [ActionReceipt]) {
        self.privateModeEnabled = privateModeEnabled
        self.bridgeState = bridgeState
        self.permissionIssues = permissionIssues
        self.recentReceipts = recentReceipts
    }
}
