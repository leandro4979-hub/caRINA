import Foundation

public enum RevocationEffectObservation: Sendable, Equatable {
    case noCommittedEffect
    case committedEffect
}

public enum RevocationCompletion: Sendable, Equatable {
    case incomplete
    case effectsVerified
    case violated
}

public enum RevocationOutcomeError: Error, Sendable, Equatable {
    case unknownGateway(String)
    case staleInstallation(gatewayID: String, installedSequence: UInt64)
}

/// Tracks the evidence required to close one revocation transaction.
///
/// Receiver persistence is not enforcement. A revocation is complete only
/// after every gateway in the frozen population has installed the required
/// sequence and an independent observer has reported no committed effect for
/// every gateway after the observation window closes.
public struct RevocationOutcomeMonitor: Sendable {
    public let revocationID: UUID
    public let sequence: UInt64
    public let observationDeadline: Date
    public let gatewayIDs: Set<String>

    private var receiverPersisted = false
    private var installedSequences: [String: UInt64] = [:]
    private var effectObservations: [String: RevocationEffectObservation] = [:]
    private var observedViolation = false

    public init(
        revocationID: UUID,
        sequence: UInt64,
        gatewayIDs: Set<String>,
        observationDeadline: Date
    ) {
        self.revocationID = revocationID
        self.sequence = sequence
        self.gatewayIDs = gatewayIDs
        self.observationDeadline = observationDeadline
    }

    public mutating func recordReceiverPersistence() {
        receiverPersisted = true
    }

    public mutating func recordGatewayInstallation(
        gatewayID: String,
        sequence installedSequence: UInt64
    ) throws {
        try requireKnownGateway(gatewayID)
        guard installedSequence >= sequence else {
            throw RevocationOutcomeError.staleInstallation(
                gatewayID: gatewayID,
                installedSequence: installedSequence
            )
        }

        installedSequences[gatewayID] = max(
            installedSequences[gatewayID] ?? installedSequence,
            installedSequence
        )
    }

    public mutating func recordEffectObservation(
        gatewayID: String,
        observation: RevocationEffectObservation
    ) throws {
        try requireKnownGateway(gatewayID)

        if observation == .committedEffect {
            observedViolation = true
        }

        // A committed effect is sticky and cannot be erased by later evidence.
        if effectObservations[gatewayID] != .committedEffect {
            effectObservations[gatewayID] = observation
        }
    }

    /// A gateway remains fenced until receiver persistence and a fresh
    /// installation receipt are both present.
    public func isGatewayFenced(_ gatewayID: String) -> Bool {
        guard gatewayIDs.contains(gatewayID), receiverPersisted else {
            return true
        }
        return (installedSequences[gatewayID] ?? 0) < sequence
    }

    public func completion(at now: Date) -> RevocationCompletion {
        if observedViolation {
            return .violated
        }

        guard receiverPersisted,
              !gatewayIDs.isEmpty,
              now >= observationDeadline else {
            return .incomplete
        }

        for gatewayID in gatewayIDs {
            guard (installedSequences[gatewayID] ?? 0) >= sequence,
                  effectObservations[gatewayID] == .noCommittedEffect else {
                return .incomplete
            }
        }

        return .effectsVerified
    }

    private func requireKnownGateway(_ gatewayID: String) throws {
        guard gatewayIDs.contains(gatewayID) else {
            throw RevocationOutcomeError.unknownGateway(gatewayID)
        }
    }
}
