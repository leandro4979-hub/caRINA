import XCTest
@testable import Carina

final class SafariAuthorizationBoundaryTests: XCTestCase {
    private struct AllowingVerifier: CarinaAuthorityBindingVerifier {
        func verify(_ authorization: ExecutionAuthorization) async -> Bool { true }
    }

    private func authorization(
        tabId: Int = 7,
        frameId: Int = 0,
        origin: String = "https://www.youtube.com",
        issuedAt: Int = 1_000,
        expiresAt: Int = 2_000
    ) -> ExecutionAuthorization {
        let base = ExecutionAuthorization(
            type: "EXECUTION_AUTHORIZATION",
            version: 1,
            authorizationId: String(repeating: "a", count: 32),
            requestId: String(repeating: "b", count: 32),
            nonce: String(repeating: "c", count: 32),
            candidateId: "candidate-1",
            pluginId: "youtube",
            intent: "SkipInterruption",
            action: "click",
            tabId: tabId,
            frameId: frameId,
            origin: origin,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            executionFingerprint: String(repeating: "0", count: 64),
            authorityBinding: String(repeating: "1", count: 64)
        )

        return ExecutionAuthorization(
            type: base.type,
            version: base.version,
            authorizationId: base.authorizationId,
            requestId: base.requestId,
            nonce: base.nonce,
            candidateId: base.candidateId,
            pluginId: base.pluginId,
            intent: base.intent,
            action: base.action,
            tabId: base.tabId,
            frameId: base.frameId,
            origin: base.origin,
            issuedAt: base.issuedAt,
            expiresAt: base.expiresAt,
            executionFingerprint: ExecutionAuthorizationStore.fingerprint(for: base),
            authorityBinding: base.authorityBinding
        )
    }

    func testDefaultVerifierFailsClosed() async throws {
        let boundary = SafariAuthorizationBoundary()
        let auth = authorization()
        try await boundary.stage(auth)

        await XCTAssertThrowsErrorAsync {
            try await boundary.consume(
                authorizationId: auth.authorizationId,
                context: SafariExecutionContext(tabId: auth.tabId, frameId: auth.frameId, origin: auth.origin),
                now: 1_500
            )
        } expected: { error in
            XCTAssertEqual(error as? AuthorizationBoundaryError, .authorityBindingRejected)
        }
    }

    func testAuthorizationIsSingleUse() async throws {
        let boundary = SafariAuthorizationBoundary(verifier: AllowingVerifier())
        let auth = authorization()
        try await boundary.stage(auth)

        _ = try await boundary.consume(
            authorizationId: auth.authorizationId,
            context: SafariExecutionContext(tabId: auth.tabId, frameId: auth.frameId, origin: auth.origin),
            now: 1_500
        )

        await XCTAssertThrowsErrorAsync {
            try await boundary.consume(
                authorizationId: auth.authorizationId,
                context: SafariExecutionContext(tabId: auth.tabId, frameId: auth.frameId, origin: auth.origin),
                now: 1_500
            )
        } expected: { error in
            XCTAssertEqual(error as? AuthorizationBoundaryError, .authorizationAlreadyConsumed)
        }
    }

    func testContextMismatchConsumesAndRejectsAuthorization() async throws {
        let boundary = SafariAuthorizationBoundary(verifier: AllowingVerifier())
        let auth = authorization(tabId: 7)
        try await boundary.stage(auth)

        await XCTAssertThrowsErrorAsync {
            try await boundary.consume(
                authorizationId: auth.authorizationId,
                context: SafariExecutionContext(tabId: 8, frameId: 0, origin: auth.origin),
                now: 1_500
            )
        } expected: { error in
            XCTAssertEqual(error as? AuthorizationBoundaryError, .contextMismatch)
        }

        await XCTAssertThrowsErrorAsync {
            try await boundary.consume(
                authorizationId: auth.authorizationId,
                context: SafariExecutionContext(tabId: auth.tabId, frameId: auth.frameId, origin: auth.origin),
                now: 1_500
            )
        } expected: { error in
            XCTAssertEqual(error as? AuthorizationBoundaryError, .authorizationAlreadyConsumed)
        }
    }

    func testExpiredAuthorizationIsRejectedBeforeDelivery() async throws {
        let boundary = SafariAuthorizationBoundary(verifier: AllowingVerifier())
        let auth = authorization(issuedAt: 1_000, expiresAt: 1_200)
        try await boundary.stage(auth)

        await XCTAssertThrowsErrorAsync {
            try await boundary.consume(
                authorizationId: auth.authorizationId,
                context: SafariExecutionContext(tabId: auth.tabId, frameId: auth.frameId, origin: auth.origin),
                now: 1_201
            )
        } expected: { error in
            XCTAssertEqual(error as? AuthorizationBoundaryError, .expiredAuthorization)
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @escaping () async throws -> T,
    expected: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        expected(error)
    }
}
