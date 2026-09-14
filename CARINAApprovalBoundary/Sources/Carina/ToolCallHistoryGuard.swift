import CryptoKit
import Foundation

public struct DuplicateToolCallError: Error, Sendable, Equatable, Codable {
    public let code: String
    public let toolName: String
    public let callHash: String
    public let message: String

    public init(toolName: String, callHash: String) {
        self.code = "duplicate_tool_call"
        self.toolName = toolName
        self.callHash = callHash
        self.message = "This tool call matches an earlier call in the same session. Choose a different strategy or change the effective arguments."
    }
}

/// Session-scoped semantic duplicate protection for agent tool calls.
///
/// Unlike replay protection, this guard intentionally ignores transport-level
/// idempotency material. A model cannot evade duplicate detection by emitting a
/// fresh request ID, nonce, or idempotency key while repeating the same action.
public actor ToolCallHistoryGuard {
    private struct SessionHistory: Sendable {
        var hashes: Set<String> = []
        var insertionOrder: [String] = []
    }

    private var histories: [UUID: SessionHistory] = [:]
    private let maxEntriesPerSession: Int

    public init(maxEntriesPerSession: Int = 512) {
        precondition(maxEntriesPerSession > 0)
        self.maxEntriesPerSession = maxEntriesPerSession
    }

    /// Reserves a semantic tool-call hash for the session.
    /// - Returns: The SHA-256 hash of the canonicalized tool name + sanitized arguments.
    /// - Throws: `DuplicateToolCallError` when the same semantic call was already reserved.
    @discardableResult
    public func reserve(
        sessionID: UUID,
        toolName: String,
        arguments: [String: String]
    ) throws -> String {
        let callHash = Self.makeHash(toolName: toolName, arguments: arguments)
        var history = histories[sessionID] ?? SessionHistory()

        guard !history.hashes.contains(callHash) else {
            throw DuplicateToolCallError(toolName: toolName, callHash: callHash)
        }

        history.hashes.insert(callHash)
        history.insertionOrder.append(callHash)

        if history.insertionOrder.count > maxEntriesPerSession {
            let evicted = history.insertionOrder.removeFirst()
            history.hashes.remove(evicted)
        }

        histories[sessionID] = history
        return callHash
    }

    public func reset(sessionID: UUID) {
        histories.removeValue(forKey: sessionID)
    }

    public func resetAll() {
        histories.removeAll(keepingCapacity: false)
    }

    public static func makeHash(
        toolName: String,
        arguments: [String: String]
    ) -> String {
        let sanitized = sanitizedArguments(arguments)
        var canonical = Data()

        appendLengthPrefixed(toolName, to: &canonical)
        for key in sanitized.keys.sorted() {
            appendLengthPrefixed(key, to: &canonical)
            appendLengthPrefixed(sanitized[key] ?? "", to: &canonical)
        }

        let digest = SHA256.hash(data: canonical)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Removes secrets from the hash input and neutralizes transport-only keys.
    /// Secret values are deliberately replaced with a fixed marker so token
    /// rotation cannot make an otherwise identical action look new.
    public static func sanitizedArguments(
        _ arguments: [String: String]
    ) -> [String: String] {
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(arguments.count)

        for (key, value) in arguments {
            let normalizedKey = key.lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")

            if transportOnlyKeys.contains(normalizedKey) {
                sanitized[key] = "<transport>"
            } else if sensitiveKeyFragments.contains(where: normalizedKey.contains) {
                sanitized[key] = "<redacted>"
            } else {
                sanitized[key] = value
            }
        }

        return sanitized
    }

    private static let transportOnlyKeys: Set<String> = [
        "idempotencykey",
        "idempotency_key",
        "requestid",
        "request_id",
        "nonce",
        "traceid",
        "trace_id"
    ]

    private static let sensitiveKeyFragments: [String] = [
        "authorization",
        "password",
        "passwd",
        "secret",
        "api_key",
        "apikey",
        "access_token",
        "refresh_token",
        "cookie"
    ]

    private static func appendLengthPrefixed(
        _ value: String,
        to data: inout Data
    ) {
        let bytes = Data(value.utf8)
        var length = UInt64(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
}
