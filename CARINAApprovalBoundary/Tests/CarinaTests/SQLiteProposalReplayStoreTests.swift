import Foundation
import XCTest
@testable import Carina

final class SQLiteProposalReplayStoreTests: XCTestCase {
    func testReservationSurvivesRestart() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let proposalID = UUID()
        let digest = String(repeating: "a", count: 64)

        do {
            let store = try SQLiteProposalReplayStore(databaseURL: databaseURL)
            XCTAssertEqual(
                try store.reserve(proposalID: proposalID, digest: digest),
                .reserved
            )
        }

        let restarted = try SQLiteProposalReplayStore(databaseURL: databaseURL)
        XCTAssertEqual(
            try restarted.reserve(proposalID: proposalID, digest: digest),
            .proposalAlreadyReserved
        )
        XCTAssertEqual(
            try restarted.reserve(proposalID: UUID(), digest: digest),
            .digestAlreadyReserved
        )
    }

    func testConcurrentCrossConnectionReservationHasOneWinner() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let proposalID = UUID()
        let digest = String(repeating: "b", count: 64)
        let first = try SQLiteProposalReplayStore(databaseURL: databaseURL)
        let second = try SQLiteProposalReplayStore(databaseURL: databaseURL)

        async let firstResult = reserve(
            store: first,
            proposalID: proposalID,
            digest: digest
        )
        async let secondResult = reserve(
            store: second,
            proposalID: proposalID,
            digest: digest
        )

        let results = try await [firstResult, secondResult]
        XCTAssertEqual(results.filter { $0 == .reserved }.count, 1)
        XCTAssertEqual(results.filter { $0 == .proposalAlreadyReserved }.count, 1)
    }

    func testDatabaseUsesOwnerOnlyPermissions() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        _ = try SQLiteProposalReplayStore(databaseURL: databaseURL)

        let databaseAttributes = try FileManager.default.attributesOfItem(
            atPath: databaseURL.path
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: databaseURL.deletingLastPathComponent().path
        )

        XCTAssertEqual(
            (databaseAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertEqual(
            (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )
    }

    private func reserve(
        store: SQLiteProposalReplayStore,
        proposalID: UUID,
        digest: String
    ) async throws -> ProposalReplayReservation {
        try store.reserve(proposalID: proposalID, digest: digest)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "carina-proposal-replay-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("proposal-replay.sqlite")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(
            at: url.deletingLastPathComponent()
        )
    }
}
