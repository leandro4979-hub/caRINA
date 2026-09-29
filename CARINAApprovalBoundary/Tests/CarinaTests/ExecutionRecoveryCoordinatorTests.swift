import XCTest
@testable import Carina

final class ExecutionRecoveryCoordinatorTests: XCTestCase {
    private let coordinator = ExecutionRecoveryCoordinator()

    func testCrashAfterReservationContinuesOnlyWithPreStateAndFreshAuthorization() throws {
        let reservation = makeReservation(state: .reserved)
        let observation = RecoveryObservation(
            reservationState: .reserved,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: false
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .continueExecution
        )
    }

    func testReservedWithPostStateQuarantinesAsImpossible() throws {
        let reservation = makeReservation(state: .reserved)
        let observation = RecoveryObservation(
            reservationState: .reserved,
            preStateMatches: false,
            postStateMatches: true,
            authorizationConsumed: false
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.impossibleState)
        )
    }

    func testReservedWithConsumedAuthorizationQuarantines() throws {
        let reservation = makeReservation(state: .reserved)
        let observation = RecoveryObservation(
            reservationState: .reserved,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.authorizationStateMismatch)
        )
    }

    func testCrashAfterExecutionCompletedButBeforeCommitRecoversCommitted() throws {
        let reservation = makeReservation(state: .executing)
        let observation = RecoveryObservation(
            reservationState: .executing,
            preStateMatches: false,
            postStateMatches: true,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .recoverAsCommitted
        )
    }

    func testCrashBeforeMutationWithConsumedAuthorizationBecomesRetryable() throws {
        let reservation = makeReservation(state: .executing)
        let observation = RecoveryObservation(
            reservationState: .executing,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .safeToRetry
        )
    }

    func testExecutingWithoutConsumedAuthorizationQuarantines() throws {
        let reservation = makeReservation(state: .executing)
        let observation = RecoveryObservation(
            reservationState: .executing,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: false
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.authorizationStateMismatch)
        )
    }

    func testHalfMutatedFilesystemQuarantines() throws {
        let reservation = makeReservation(state: .executing)
        let observation = RecoveryObservation(
            reservationState: .executing,
            preStateMatches: false,
            postStateMatches: false,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.partialMutation)
        )
    }

    func testCommittedReservationRequiresPostStateReality() throws {
        let reservation = makeReservation(state: .committed)
        let badObservation = RecoveryObservation(
            reservationState: .committed,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: badObservation),
            .quarantine(.reservationCorruption)
        )
    }

    func testFailedIsNeverImplicitlyRetryable() throws {
        let reservation = makeReservation(state: .failed)
        let observation = RecoveryObservation(
            reservationState: .failed,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .quarantine(.reservationCorruption)
        )
    }

    func testIndeterminateCanRecoverCommittedWhenRealityIsExact() throws {
        let reservation = makeReservation(state: .indeterminate)
        let observation = RecoveryObservation(
            reservationState: .indeterminate,
            preStateMatches: false,
            postStateMatches: true,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .recoverAsCommitted
        )
    }

    func testIndeterminateCanBecomeRetryableOnlyWhenPreStateMatches() throws {
        let reservation = makeReservation(state: .indeterminate)
        let observation = RecoveryObservation(
            reservationState: .indeterminate,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: true
        )

        XCTAssertEqual(
            try coordinator.decide(reservation: reservation, actual: observation),
            .safeToRetry
        )
    }

    func testObservationStateMustMatchReservationState() throws {
        let reservation = makeReservation(state: .executing)
        let observation = RecoveryObservation(
            reservationState: .reserved,
            preStateMatches: true,
            postStateMatches: false,
            authorizationConsumed: false
        )

        XCTAssertThrowsError(
            try coordinator.decide(reservation: reservation, actual: observation)
        ) {
            XCTAssertEqual(
                $0 as? ExecutionRecoveryError,
                .inconsistentObservationState(expected: .executing, observed: .reserved)
            )
        }
    }

    func testCASFailureReloadsAndReevaluatesReality() async throws {
        let initial = makeReservation(state: .executing)
        let store = RacingReservationStore(initial: initial)
        let inspector = RacingRealityInspector()

        let decision = try await coordinator.recover(
            key: initial.idempotencyKey,
            store: store,
            inspector: inspector
        )

        XCTAssertEqual(decision, .alreadyCommitted)
        let final = try await store.load(initial.idempotencyKey)
        XCTAssertEqual(final?.state, .committed)
        let observationCount = await inspector.observationCount
        XCTAssertEqual(observationCount, 2)
    }

    private func makeReservation(state: ReservationState) -> MutationReservation {
        MutationReservation(
            idempotencyKey: "proposal-001",
            proposalID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            validationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            authorizationID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            authorityDigest: String(repeating: "a", count: 64),
            registryVersion: 7,
            attempt: 1,
            state: state
        )
    }
}

private actor RacingReservationStore: MutationReservationStore {
    private var reservation: MutationReservation
    private var firstCAS = true

    init(initial: MutationReservation) {
        self.reservation = initial
    }

    func load(_ idempotencyKey: String) async throws -> MutationReservation? {
        reservation.idempotencyKey == idempotencyKey ? reservation : nil
    }

    func compareAndSet(
        idempotencyKey: String,
        expectedState: ReservationState,
        newState: ReservationState
    ) async throws -> Bool {
        guard reservation.idempotencyKey == idempotencyKey else { return false }

        if firstCAS {
            firstCAS = false
            // Simulate another recovery actor proving and committing the action
            // before this actor can persist its stale decision.
            reservation = reservation.withState(.committed)
            return false
        }

        guard reservation.state == expectedState else { return false }
        reservation = reservation.withState(newState)
        return true
    }
}

private actor RacingRealityInspector: FilesystemRealityInspecting {
    private(set) var observationCount = 0

    func observe(reservation: MutationReservation) async throws -> RecoveryObservation {
        observationCount += 1

        switch reservation.state {
        case .executing:
            return RecoveryObservation(
                reservationState: .executing,
                preStateMatches: true,
                postStateMatches: false,
                authorizationConsumed: true
            )
        case .committed:
            return RecoveryObservation(
                reservationState: .committed,
                preStateMatches: false,
                postStateMatches: true,
                authorizationConsumed: true
            )
        default:
            return RecoveryObservation(
                reservationState: reservation.state,
                preStateMatches: false,
                postStateMatches: false,
                authorizationConsumed: false
            )
        }
    }
}
