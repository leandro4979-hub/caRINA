import CryptoKit
import Foundation

/// Phase 2 native boundary for Safari Web Extension execution authorization.
///
/// This layer is deliberately fail-closed. It does not decide policy and it does
/// not mint EXECUTION_AUTHORIZATION values. CARINA's authority layer must issue
/// an authorization first, and the native boundary may only validate and deliver
/// an already-issued authorization to the extension background runtime.
protocol CarinaExecutionAuthorization: Codable, Sendable {
    var type: String { get }
    var version: Int { get }
    var authorizationId: String { get }
    var requestId: String { get }
    var nonce: String { get }
    var candidateId: String { get }
    var pluginId: String { get }
    var intent: String { get }
    var action: String { get }
    var tabId: Int { get }
    var frameId: Int { get }
    var origin: String { get }
    var issuedAt: Int { get }
    var expiresAt: Int { get }
    var executionFingerprint: String { get }
    var authorityBinding: String { get }
}

struct ExecutionAuthorization: CarinaExecutionAuthorization, Equatable {
    let type: String
    let version: Int
    let authorizationId: String
    let requestId: String
    let nonce: String
    let candidateId: String
    let pluginId: String
    let intent: String
    let action: String
    let tabId: Int
    let frameId: Int
    let origin: String
    let issuedAt: Int
    let expiresAt: Int
    let executionFingerprint: String
    let authorityBinding: String
}

struct SafariExecutionContext: Equatable, Sendable {
    let tabId: Int
    let frameId: Int
    let origin: String
}

enum AuthorizationBoundaryError: Error, Equatable {
    case malformedMessage
    case unsupportedMessage
    case invalidAuthorization
    case expiredAuthorization
    case contextMismatch
    case fingerprintMismatch
    case authorityBindingRejected
    case authorizationAlreadyConsumed
    case authorizationNotAvailable
}

/// The authority verifier is intentionally an injection point.
///
/// The browser/native boundary must not invent the cryptographic semantics for
/// authorityBinding. The Authority Spine owns issuance and verification rules.
protocol CarinaAuthorityBindingVerifier: Sendable {
    func verify(_ authorization: ExecutionAuthorization) async -> Bool
}

/// Fail-closed default. Until the Authority Spine provides a concrete verifier,
/// no EXECUTION_AUTHORIZATION can cross this boundary.
struct UnconfiguredAuthorityBindingVerifier: CarinaAuthorityBindingVerifier {
    func verify(_ authorization: ExecutionAuthorization) async -> Bool {
        false
    }
}

actor ExecutionAuthorizationStore {
    private var pending: [String: ExecutionAuthorization] = [:]
    private var consumed: Set<String> = []

    func stage(_ authorization: ExecutionAuthorization) throws {
        guard authorization.type == "EXECUTION_AUTHORIZATION",
              authorization.version == 1,
              authorization.action == "click",
              !authorization.authorizationId.isEmpty,
              !authorization.requestId.isEmpty,
              !authorization.nonce.isEmpty,
              authorization.issuedAt >= 0,
              authorization.expiresAt >= authorization.issuedAt else {
            throw AuthorizationBoundaryError.invalidAuthorization
        }

        guard consumed.contains(authorization.authorizationId) == false,
              pending[authorization.authorizationId] == nil else {
            throw AuthorizationBoundaryError.authorizationAlreadyConsumed
        }

        pending[authorization.authorizationId] = authorization
    }

    /// Atomically consumes an authorization before it is returned to the browser.
    /// A second request for the same authorization can never receive it.
    func consume(
        authorizationId: String,
        context: SafariExecutionContext,
        now: Int,
        verifier: CarinaAuthorityBindingVerifier
    ) async throws -> ExecutionAuthorization {
        guard consumed.contains(authorizationId) == false else {
            throw AuthorizationBoundaryError.authorizationAlreadyConsumed
        }

        guard let authorization = pending.removeValue(forKey: authorizationId) else {
            throw AuthorizationBoundaryError.authorizationNotAvailable
        }

        guard now >= authorization.issuedAt,
              authorization.expiresAt >= authorization.issuedAt,
              now <= authorization.expiresAt else {
            consumed.insert(authorization.authorizationId)
            throw AuthorizationBoundaryError.expiredAuthorization
        }

        guard authorization.tabId == context.tabId,
              authorization.frameId == context.frameId,
              authorization.origin == context.origin else {
            consumed.insert(authorization.authorizationId)
            throw AuthorizationBoundaryError.contextMismatch
        }

        guard Self.fingerprint(for: authorization) == authorization.executionFingerprint else {
            consumed.insert(authorization.authorizationId)
            throw AuthorizationBoundaryError.fingerprintMismatch
        }

        guard await verifier.verify(authorization) else {
            consumed.insert(authorization.authorizationId)
            throw AuthorizationBoundaryError.authorityBindingRejected
        }

        consumed.insert(authorization.authorizationId)
        return authorization
    }

    static func fingerprint(for authorization: ExecutionAuthorization) -> String {
        let canonical = [
            authorization.requestId,
            authorization.nonce,
            authorization.candidateId,
            authorization.pluginId,
            authorization.intent,
            authorization.action,
            String(authorization.tabId),
            String(authorization.frameId),
            authorization.origin,
        ].joined(separator: "\n")

        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Native boundary coordinator. It accepts only extension requests for an
/// already-issued authorization and never creates one from browser input.
actor SafariAuthorizationBoundary {
    private let store: ExecutionAuthorizationStore
    private let verifier: CarinaAuthorityBindingVerifier

    init(
        store: ExecutionAuthorizationStore = ExecutionAuthorizationStore(),
        verifier: CarinaAuthorityBindingVerifier = UnconfiguredAuthorityBindingVerifier()
    ) {
        self.store = store
        self.verifier = verifier
    }

    func stage(_ authorization: ExecutionAuthorization) async throws {
        try await store.stage(authorization)
    }

    func consume(
        authorizationId: String,
        context: SafariExecutionContext,
        now: Int
    ) async throws -> ExecutionAuthorization {
        try await store.consume(
            authorizationId: authorizationId,
            context: context,
            now: now,
            verifier: verifier
        )
    }
}
