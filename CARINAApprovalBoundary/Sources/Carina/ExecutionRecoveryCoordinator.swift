import Foundation

public enum ReservationState: String, Codable, Sendable, Equatable {
    case reserved
    case executing
    case committed
    case retryable
    case failed
    case indeterminate
}

public struct MutationReservation: Codable, Sendable, Equatable {
    public let idempotencyKey: String
    public let proposalID: UUID
    public let validationID: UUID
    public let authorizationID: UUID
    public let authorityDigest: String
    public let registryVersion: UInt64
    public let attempt: UInt64
    public let state: ReservationState

    public init(
        idempotencyKey: String,
        proposalID: UUID,
        validationID: UUID,
        authorizationID: UUID,
        authorityDigest: String,
        registryVersion: UInt64,
        attempt: UInt64,
        state: ReservationState
    ) {
        self.idempotencyKey = idempotencyKey
        self.proposalID = proposalID
        self.validationID = validationID
        self.authorizationID = authorizationID
        self.authorityDigest = authorityDigest
        self.registryVersion = registryVersion
        self.attempt = attempt
        self.state = state
    }

    public func withState(_ newState: ReservationState) -> MutationReservation {
        MutationReservation(
            idempotencyKey: idempotencyKey,
            proposalID: proposalID,
            validationID: validationID,
            authorizationID: authorizationID,
            authorityDigest: authorityDigest,
            registryVersion: registryVersion,
            attempt: attempt,
            state: newState
        )
    }
}

public struct RecoveryObservation: Sendable, Equatable {
    public let reservationState: ReservationState
    public let preStateMatches: Bool
    public let postStateMatches: Bool
    public let authorizationConsumed: Bool

    public init(
        reservationState: ReservationState,
        preStateMatches: Bool,
        postStateMatches: Bool,
        authorizationConsumed: Bool
    ) {
        self.reservationState = reservationState
        self.preStateMatches = preStateMatches
        self.postStateMatches = postStateMatches
        self.authorizationConsumed = authorizationConsumed
    }
}

public enum RecoveryReason: Sendable, Equatable {
    case impossibleState
    case ambiguousFilesystemState
    case authorizationStateMismatch
    case partialMutation
    case reservationCorruption
}

public enum RecoveryDecision: Sendable, Equatable {
    case continueExecution
    case safeToRetry
    case recoverAsCommitted
    case alreadyCommitted
    case quarantine(RecoveryReason)
}

public enum ExecutionRecoveryError: Error, Sendable, Equatable {
    case missingReservation(String)
    case inconsistentObservationState(expected: ReservationState, observed: ReservationState)
    case compareAndSetStarvation(String)
}

public protocol MutationReservationStore: Sendable {
    func load(_ idempotencyKey: String) async throws -> MutationReservation?

    func compareAndSet(
        idempotencyKey: String,
        expectedState: ReservationState,
        newState: ReservationState
    ) async throws -> Bool
}

public protocol FilesystemRealityInspecting: Sendable {
    func observe(reservation: MutationReservation) async throws -> RecoveryObservation
}

public struct ExecutionRecoveryCoordinator: Sendable {
    public let maximumCASAttempts: Int

    public init(maximumCASAttempts: Int = 32) {
        self.maximumCASAttempts = maximumCASAttempts
    }

    public func decide(
        reservation: MutationReservation,
        actual: RecoveryObservation
    ) throws -> RecoveryDecision {
        guard reservation.state == actual.reservationState else {
            throw ExecutionRecoveryError.inconsistentObservationState(
                expected: reservation.state,
                observed: actual.reservationState
            )
        }

        switch reservation.state {
        case .committed:
            guard actual.postStateMatches, !actual.preStateMatches else {
                return .quarantine(.reservationCorruption)
            }
            return .alreadyCommitted

        case .reserved:
            return recoverReserved(actual)

        case .executing:
            return recoverExecuting(actual)

        case .retryable:
            guard actual.preStateMatches,
                  !actual.postStateMatches
            else {
                return .quarantine(.ambiguousFilesystemState)
            }
            return .safeToRetry

        case .indeterminate:
            return resolveIndeterminate(actual)

        case .failed:
            return .quarantine(.reservationCorruption)
        }
    }

    public func recover(
        key: String,
        store: any MutationReservationStore,
        inspector: any FilesystemRealityInspecting
    ) async throws -> RecoveryDecision {
        var attempts = 0

        while attempts < maximumCASAttempts {
            attempts += 1

            guard let reservation = try await store.load(key) else {
                throw ExecutionRecoveryError.missingReservation(key)
            }

            let observation = try await inspector.observe(reservation: reservation)
            let decision = try decide(reservation: reservation, actual: observation)

            guard let nextState = persistedState(for: decision) else {
                return decision
            }

            if nextState == reservation.state {
                return decision
            }

            let changed = try await store.compareAndSet(
                idempotencyKey: key,
                expectedState: reservation.state,
                newState: nextState
            )

            if changed {
                return decision
            }

            // Another recovery actor won the transition. Reload reservation and
            // filesystem reality rather than carrying forward a stale decision.
        }

        throw ExecutionRecoveryError.compareAndSetStarvation(key)
    }

    private func recoverReserved(_ observation: RecoveryObservation) -> RecoveryDecision {
        if observation.preStateMatches &&
            !observation.postStateMatches &&
            !observation.authorizationConsumed {
            return .continueExecution
        }

        if observation.postStateMatches {
            return .quarantine(.impossibleState)
        }

        if observation.authorizationConsumed {
            return .quarantine(.authorizationStateMismatch)
        }

        return .quarantine(.ambiguousFilesystemState)
    }

    private func recoverExecuting(_ observation: RecoveryObservation) -> RecoveryDecision {
        if observation.postStateMatches &&
            !observation.preStateMatches &&
            observation.authorizationConsumed {
            return .recoverAsCommitted
        }

        if observation.preStateMatches &&
            !observation.postStateMatches &&
            observation.authorizationConsumed {
            return .safeToRetry
        }

        if observation.preStateMatches &&
            !observation.postStateMatches &&
            !observation.authorizationConsumed {
            return .quarantine(.authorizationStateMismatch)
        }

        return .quarantine(.partialMutation)
    }

    private func resolveIndeterminate(_ observation: RecoveryObservation) -> RecoveryDecision {
        if observation.postStateMatches &&
            !observation.preStateMatches &&
            observation.authorizationConsumed {
            return .recoverAsCommitted
        }

        if observation.preStateMatches &&
            !observation.postStateMatches {
            return .safeToRetry
        }

        return .quarantine(.ambiguousFilesystemState)
    }

    private func persistedState(for decision: RecoveryDecision) -> ReservationState? {
        switch decision {
        case .continueExecution, .alreadyCommitted:
            return nil
        case .safeToRetry:
            return .retryable
        case .recoverAsCommitted:
            return .committed
        case .quarantine:
            return .indeterminate
        }
    }
}
