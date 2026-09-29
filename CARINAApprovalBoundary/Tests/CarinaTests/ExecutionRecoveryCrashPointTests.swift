import XCTest
@testable import Carina

final class ExecutionRecoveryCrashPointTests: XCTestCase {
    func testRetryableRequiresExactPreState() throws {
        let coordinator = ExecutionRecoveryCoordinator()
        let reservation = makeReservation(state: .retryable)
        let observation = RecoveryObservation(
            reservationState: .retryable,
            preStateMatches: false,
            postStateMatches: false,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.ambiguousFilesystemState)
        )
    }

    func testRetryableRejectsAlreadyMutatedFilesystem() throws {
        let coordinator = ExecutionRecoveryCoordinator()
        let reservation = makeReservation(state: .retryable)
        let observation = RecoveryObservation(
            reservationState: .retryable,
            preStateMatches: false,
            postStateMatches: true,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.ambiguousFilesystemState)
        )
    }

    func testCommittedWithBothPreAndPostMatchingQuarantines() throws {
        let coordinator = ExecutionRecoveryCoordinator()
        let reservation = makeReservation(state: .committed)
        let observation = RecoveryObservation(
            reservationState: .committed,
            preStateMatches: true,
            postStateMatches: true,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.reservationCorruption)
        )
    }

    func testIndeterminateWithNeitherStateMatchingStaysQuarantined() throws {
        let coordinator = ExecutionRecoveryCoordinator()
        let reservation = makeReservation(state: .indeterminate)
        let observation = RecoveryObservation(
            reservationState: .indeterminate,
            preStateMatches: false,
            postStateMatches: false,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.ambiguousFilesystemState)
        )
    }

    func testIndeterminatePostStateWithoutConsumedAuthorizationQuarantines() throws {
        let coordinator = ExecutionRecoveryCoordinator()
        let reservation = makeReservation(state: .indeterminate)
        let observation = RecoveryObservation(
            reservationState: .indeterminate,
            preStateMatches: false,
            postStateMatches: true,
            authorizationConsumed: false
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.ambiguousFilesystemState)
        )
    }

    func testExecutingWithBothPreAndPostMatchingQuarantinesPartialMutation() throws {
        let coordinator = ExecutionRecoveryCoordinator()
        let reservation = makeReservation(state: .executing)
        let observation = RecoveryObservation(
            reservationState: .executing,
            preStateMatches: true,
            postStateMatches: true,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.partialMutation)
        )
    }

    func testCASStarvationFailsClosed() async {
        let key = "op-starve"
        let coordinator = ExecutionRecoveryCoordinator(maximumCASAttempts: 3)
        let store = AlwaysConflictingReservationStore(
            reservation: makeReservation(key: key, state: .executing)
        )
        let inspector = MatchingPreStateInspector()

        do {
            _ = try await coordinator.recover(
                key: key,
                store: store,
                inspector: inspector
            )
            XCTFail("Expected compare-and-set starvation")
        } catch {
            XCTAssertEqual(
                error as? ExecutionRecoveryError,
                .compareAndSetStarvation(key)
            )
        }
    }

    func testMissingReservationFailsClosed() async {
        let coordinator = ExecutionRecoveryCoordinator()
        let store = EmptyReservationStore()

        do {
            _ = try await coordinator.recover(
                key: "missing",
                store: store,
                inspector: MatchingPreStateInspector()
            )
            XCTFail("Expected missing reservation")
        } catch {
            XCTAssertEqual(
                error as? ExecutionRecoveryError,
                .missingReservation("missing")
            )
        }
    }

    private func makeReservation(
        key: String = "op",
        state: ReservationState
    ) -> MutationReservation {
        MutationReservation(
            idempotencyKey: key,
            proposalID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            validationID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            authorizationID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            authorityDigest: String(repeating: "d", count: 64),
            registryVersion: 7,
            attempt: 1,
            state: state
        )
    }
}

private actor AlwaysConflictingReservationStore: MutationReservationStore {
    private let reservation: MutationReservation

    init(reservation: MutationReservation) {
        self.reservation = reservation
    }

    func load(_ idempotencyKey: String) async throws -> MutationReservation? {
        reservation.idempotencyKey == idempotencyKey ? reservation : nil
    }

    func compareAndSet(
        idempotencyKey: String,
        expectedState: ReservationState,
        newState: ReservationState
    ) async throws -> Bool {
        false
    }
}

private actor EmptyReservationStore: MutationReservationStore {
    func load(_ idempotencyKey: String) async throws -> MutationReservation? {
        nil
    }

    func compareAndSet(
        idempotencyKey: String,
        expectedState: ReservationState,
        newState: ReservationState
    ) async throws -> Bool {
        false
    }
}

private struct MatchingPreStateInspector: FilesystemRealityInspecting {
    func observe(reservation: MutationReservation) async throws -> RecoveryObservation {
        RecoveryObservation(
            reservationState: reservation.state,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: true
        )
    }
}
