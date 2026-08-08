import XCTest
@testable import Carina

final class ReplayProtectorTests: XCTestCase {
    func testExactTupleCannotBeReservedTwice() async throws {
        let protector = ReplayProtector()
        let envelope = makeEnvelope()
        try await protector.reserve(envelope)
        do {
            try await protector.reserve(envelope)
            XCTFail("Expected replay rejection")
        } catch {
            XCTAssertEqual(
                error as? ReplayProtectionError,
                .replayDetected(ReplayKey(envelope: envelope))
            )
        }
    }

    func testChangingAnyTupleMemberCreatesDistinctReservation() async throws {
        let protector = ReplayProtector()
        try await protector.reserve(makeEnvelope())
        try await protector.reserve(makeEnvelope(sessionID: UUID()))
        try await protector.reserve(makeEnvelope(sequence: 10))
        try await protector.reserve(makeEnvelope(nonce: UUID()))
    }

    func testConcurrentDuplicateReservationHasOneWinner() async {
        let protector = ReplayProtector()
        let envelope = makeEnvelope()
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do {
                        try await protector.reserve(envelope)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        XCTAssertEqual(successes, 1)
    }
}
