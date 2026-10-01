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

public protocol ToolCallHistoryStateStore: Sendable {
    func reserveToolCall(
        sessionID: UUID,
        callHash: String,
        correlationID: UUID,
        expiresAt: Date,
        now: Date
    ) async throws -> Bool

    func releaseToolCall(correlationID: UUID) async throws
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

    private struct Correlation: Sendable {
        let sessionID: UUID
        let callHash: String
    }

    private var histories: [UUID: SessionHistory] = [:]
    private var correlations: [UUID: Correlation] = [:]
    private let maxEntriesPerSession: Int
    private let store: (any ToolCallHistoryStateStore)?
    private let retention: TimeInterval

    public init(
        maxEntriesPerSession: Int = 512,
        store: (any ToolCallHistoryStateStore)? = nil,
        retention: TimeInterval = 24 * 60 * 60
    ) {
        precondition(maxEntriesPerSession > 0)
        precondition(retention > 0)
        self.maxEntriesPerSession = maxEntriesPerSession
        self.store = store
        self.retention = retention
    }

    /// Reserves a semantic tool-call hash for the session.
    /// - Returns: The SHA-256 hash of the canonicalized tool name + sanitized arguments.
    /// - Throws: `DuplicateToolCallError` when the same semantic call was already reserved.
    @discardableResult
    public func reserve(
        sessionID: UUID,
        toolName: String,
        arguments: [String: String],
        correlationID: UUID = UUID(),
        now: Date = Date()
    ) async throws -> String {
        let callHash = Self.makeHash(toolName: toolName, arguments: arguments)

        if let store {
            let reserved = try await store.reserveToolCall(
                sessionID: sessionID,
                callHash: callHash,
                correlationID: correlationID,
                expiresAt: now.addingTimeInterval(retention),
                now: now
            )
            guard reserved else {
                throw DuplicateToolCallError(toolName: toolName, callHash: callHash)
            }
            return callHash
        }

        var history = histories[sessionID] ?? SessionHistory()

        guard !history.hashes.contains(callHash) else {
            throw DuplicateToolCallError(toolName: toolName, callHash: callHash)
        }

        history.hashes.insert(callHash)
        history.insertionOrder.append(callHash)

        if history.insertionOrder.count > maxEntriesPerSession {
            let evicted = history.insertionOrder.removeFirst()
            history.hashes.remove(evicted)
            correlations = correlations.filter {
                !($0.value.sessionID == sessionID && $0.value.callHash == evicted)
            }
        }

        histories[sessionID] = history
        correlations[correlationID] = Correlation(
            sessionID: sessionID,
            callHash: callHash
        )
        return callHash
    }

    public func release(correlationID: UUID) async throws {
        if let store {
            try await store.releaseToolCall(correlationID: correlationID)
            return
        }

        guard let correlation = correlations.removeValue(forKey: correlationID),
              var history = histories[correlation.sessionID] else {
            return
        }

        history.hashes.remove(correlation.callHash)
        history.insertionOrder.removeAll { $0 == correlation.callHash }
        if history.hashes.isEmpty {
            histories.removeValue(forKey: correlation.sessionID)
        } else {
            histories[correlation.sessionID] = history
        }
    }

    public func reset(sessionID: UUID) {
        histories.removeValue(forKey: sessionID)
        correlations = correlations.filter { $0.value.sessionID != sessionID }
    }

    public func resetAll() {
        histories.removeAll(keepingCapacity: false)
        correlations.removeAll(keepingCapacity: false)
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

    /// Removes secrets from the hash input, neutralizes transport-only keys,
    /// and reduces encoded ActionPlans to their execution-relevant semantics.
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
            } else if actionPlanKeys.contains(normalizedKey),
                      let canonicalPlan = canonicalActionPlan(value) {
                sanitized[key] = canonicalPlan
            } else if sensitiveKeyFragments.contains(where: normalizedKey.contains) {
                sanitized[key] = "<redacted>"
            } else {
                sanitized[key] = value
            }
        }

        return sanitized
    }

    private static let actionPlanKeys: Set<String> = [
        "actionplan",
        "action_plan"
    ]

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

    private static func canonicalActionPlan(_ encodedPlan: String) -> String? {
        guard let data = Data(base64Encoded: encodedPlan),
              let plan = try? JSONDecoder().decode(ActionPlan.self, from: data) else {
            return nil
        }

        var canonical = Data()
        appendLengthPrefixed(plan.capabilityID, to: &canonical)
        appendLengthPrefixed(String(plan.capabilityVersionMajor), to: &canonical)
        appendLengthPrefixed(plan.target, to: &canonical)
        for key in plan.normalizedPayload.keys.sorted() {
            appendLengthPrefixed(key, to: &canonical)
            appendLengthPrefixed(plan.normalizedPayload[key] ?? "", to: &canonical)
        }
        return canonical.base64EncodedString()
    }

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
