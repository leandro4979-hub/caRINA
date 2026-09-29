import Foundation
import XCTest
@testable import Carina

final class PersistentApprovalBoundaryTests: XCTestCase {
    func testReplayReservationSurvivesStoreRestart() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let envelope = makeEnvelope()
        do {
            let store = try SQLiteApprovalStateStore(databaseURL: databaseURL)
            let protector = ReplayProtector(store: store)
            try await protector.reserve(envelope)
        }

        let restartedStore = try SQLiteApprovalStateStore(
            databaseURL: databaseURL
        )
        let restartedProtector = ReplayProtector(store: restartedStore)
        do {
            try await restartedProtector.reserve(envelope)
            XCTFail("A restart cleared the replay reservation")
        } catch {
            XCTAssertEqual(
                error as? ReplayProtectionError,
                .replayDetected(ReplayKey(envelope: envelope))
            )
        }
    }

    func testTokenSurvivesRestartAndConsumesOnce() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let token: AuthorizationToken

        do {
            let store = try SQLiteApprovalStateStore(
                databaseURL: databaseURL
            )
            let verifier = ApprovalVerifier(store: store)
            let challenge = try await verifier.createChallenge(
                envelope: envelope,
                expiresAt: now.addingTimeInterval(30)
            )
            guard let issued = try await verifier.authorize(
                challenge: challenge,
                approved: true,
                now: now
            ) else {
                return XCTFail("Expected authorization token")
            }
            token = issued
        }

        let restartedStore = try SQLiteApprovalStateStore(
            databaseURL: databaseURL
        )
        let verifier = ApprovalVerifier(store: restartedStore)
        try await verifier.consume(
            token,
            expectedFingerprint: ApprovalFingerprint.make(for: envelope),
            now: now
        )

        do {
            try await verifier.consume(
                token,
                expectedFingerprint: ApprovalFingerprint.make(for: envelope),
                now: now
            )
            XCTFail("A consumed token was accepted twice")
        } catch {
            XCTAssertEqual(
                error as? AuthorizationError,
                .tokenUnknownOrConsumed
            )
        }
    }

    func testConcurrentCrossConnectionConsumptionHasOneWinner() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = makeEnvelope()
        let firstStore = try SQLiteApprovalStateStore(
            databaseURL: databaseURL
        )
        let issuingVerifier = ApprovalVerifier(store: firstStore)
        let challenge = try await issuingVerifier.createChallenge(
            envelope: envelope,
            expiresAt: now.addingTimeInterval(30)
        )
        guard let token = try await issuingVerifier.authorize(
            challenge: challenge,
            approved: true,
            now: now
        ) else {
            return XCTFail("Expected authorization token")
        }

        let secondStore = try SQLiteApprovalStateStore(
            databaseURL: databaseURL
        )
        let firstVerifier = ApprovalVerifier(store: firstStore)
        let secondVerifier = ApprovalVerifier(store: secondStore)
        let fingerprint = ApprovalFingerprint.make(for: envelope)

        async let first: Bool = consume(
            verifier: firstVerifier,
            token: token,
            fingerprint: fingerprint,
            now: now
        )
        async let second: Bool = consume(
            verifier: secondVerifier,
            token: token,
            fingerprint: fingerprint,
            now: now
        )
        let successes = await [first, second].filter { $0 }.count
        XCTAssertEqual(successes, 1)
    }

    func testIdempotencyReservationSurvivesRestart() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        do {
            let store = try SQLiteApprovalStateStore(
                databaseURL: databaseURL
            )
            try await IdempotencyStore(store: store).reserve("sync-001")
        }

        let restartedStore = try SQLiteApprovalStateStore(
            databaseURL: databaseURL
        )
        do {
            try await IdempotencyStore(store: restartedStore)
                .reserve("sync-001")
            XCTFail("A restart cleared the idempotency reservation")
        } catch {
            XCTAssertEqual(
                error as? IdempotencyError,
                .alreadyReserved("sync-001")
            )
        }
    }

    func testRegistryDerivesPermissionBeforeReplayReservation() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let registry = CapabilityRegistrySnapshot(
            id: "production-v1",
            capabilities: [
                Capability(
                    id: CommandIntentID.workspaceSync.rawValue,
                    allowedInputs: ["scope", "idempotencyKey"],
                    kind: .commit,
                    risk: .high
                )
            ]
        )
        let boundary = try PersistentApprovalBoundary(
            databaseURL: databaseURL,
            registry: registry,
            adapter: RecordingAdapter()
        )
        let invalid = makeEnvelope(payload: [
            "scope": "documents",
            "idempotencyKey": "sync-001",
            "unreviewed": "value"
        ])

        do {
            _ = try await boundary.prepare(envelope: invalid)
            XCTFail("Unknown input crossed registry policy")
        } catch {
            XCTAssertEqual(
                error as? ProductionPolicyError,
                .unknownInput("unreviewed")
            )
        }

        let valid = makeEnvelope()
        guard case .approvalRequired = try await boundary.prepare(
            envelope: valid
        ) else {
            return XCTFail("Registry-approved execute did not require approval")
        }
    }

    private func consume(
        verifier: ApprovalVerifier,
        token: AuthorizationToken,
        fingerprint: String,
        now: Date
    ) async -> Bool {
        do {
            try await verifier.consume(
                token,
                expectedFingerprint: fingerprint,
                now: now
            )
            return true
        } catch {
            return false
        }
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("approval.sqlite")
    }

    private func removeDatabase(at url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
    }
}
