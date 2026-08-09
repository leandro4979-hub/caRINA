import Foundation
import Darwin

public enum DurableLedgerError: Error, Sendable, Equatable {
    case corruptStore, tamperedPlan, invalidTransition, expired
}

public enum DurableOutboxState: String, Codable, Sendable { case pending, completed }

public struct DurableOutboxEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String                 // Stable executor idempotency identifier.
    public let planID: UUID
    public let correlationID: UUID
    public let plan: ActionPlan
    public var attempts: Int
    public var state: DurableOutboxState
    public let createdAt: Date
}

private struct DurableLedgerRecord: Codable {
    var plan: ActionPlan
    var state: LedgerState
}

private struct DurableLedgerStore: Codable {
    var records: [String: DurableLedgerRecord] = [:]
    var idempotency: [String: String] = [:]
    var outbox: [String: DurableOutboxEntry] = [:]
}

/// File-backed reference implementation. Every guarded state change reads,
/// validates, mutates, and atomically replaces a single store while holding an
/// advisory process lock. The outbox row is written in the same replacement as
/// the approved reservation; delivery remains at-least-once via `id`.
public actor DurableActionLedger {
    public let storeURL: URL
    private let lockURL: URL

    public init(storeURL: URL) throws {
        self.storeURL = storeURL
        self.lockURL = storeURL.appendingPathExtension("lock")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    @discardableResult
    public func reserve(_ plan: ActionPlan, now: Date = Date()) throws -> LedgerState {
        try transact { store in
            guard plan.isIntact() else { throw DurableLedgerError.tamperedPlan }
            if let planID = store.idempotency[plan.idempotencyKey], let record = store.records[planID] { return record.state }
            guard plan.kind == .commit || plan.kind == .admin else { throw DurableLedgerError.invalidTransition }
            guard plan.expiresAt > now else { throw DurableLedgerError.expired }
            let planID = plan.id.uuidString
            store.records[planID] = DurableLedgerRecord(plan: plan, state: .approved)
            store.idempotency[plan.idempotencyKey] = planID
            store.outbox[plan.idempotencyKey] = DurableOutboxEntry(id: plan.idempotencyKey, planID: plan.id, correlationID: plan.correlationID, plan: plan, attempts: 0, state: .pending, createdAt: now)
            return .approved
        }
    }

    /// Returns each incomplete delivery on every restart. Callers must present
    /// `entry.id` to their executor as its idempotency key.
    public func pendingOutbox(now: Date = Date()) throws -> [DurableOutboxEntry] {
        try transact { store in
            var pending: [DurableOutboxEntry] = []
            for key in store.outbox.keys.sorted() {
                guard var entry = store.outbox[key], entry.state == .pending else { continue }
                guard entry.plan.isIntact() else { throw DurableLedgerError.tamperedPlan }
                guard entry.plan.expiresAt > now else {
                    store.records[entry.planID.uuidString]?.state = .expired
                    entry.state = .completed
                    store.outbox[key] = entry
                    continue
                }
                entry.attempts += 1
                store.outbox[key] = entry
                pending.append(entry)
            }
            return pending
        }
    }

    public func beginDispatch(dispatchID: String, now: Date = Date()) throws {
        try transact { store in
            guard let entry = store.outbox[dispatchID], entry.state == .pending else { throw DurableLedgerError.invalidTransition }
            guard entry.plan.isIntact() else { throw DurableLedgerError.tamperedPlan }
            guard entry.plan.expiresAt > now else { throw DurableLedgerError.expired }
            guard store.records[entry.planID.uuidString]?.state == .approved else { throw DurableLedgerError.invalidTransition }
            store.records[entry.planID.uuidString]?.state = .dispatching
        }
    }

    /// Completion and outbox acknowledgement share one durable transaction.
    public func complete(dispatchID: String, verified: Bool?) throws {
        try transact { store in
            guard var entry = store.outbox[dispatchID], entry.state == .pending,
                  entry.plan.isIntact(), store.records[entry.planID.uuidString]?.state == .dispatching else { throw DurableLedgerError.invalidTransition }
            store.records[entry.planID.uuidString]?.state = verified == true ? .verified : verified == false ? .failed : .unknown
            entry.state = .completed
            store.outbox[dispatchID] = entry
        }
    }

    public func state(for plan: ActionPlan) throws -> LedgerState? {
        try transact { store in
            guard plan.isIntact() else { throw DurableLedgerError.tamperedPlan }
            return store.records[plan.id.uuidString]?.state
        }
    }

    private func transact<T>(_ body: (inout DurableLedgerStore) throws -> T) throws -> T {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw DurableLedgerError.corruptStore }
        defer { _ = close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw DurableLedgerError.corruptStore }
        defer { _ = flock(fd, LOCK_UN) }
        var store = try loadStore()
        let result = try body(&store)
        try persist(store)
        return result
    }

    private func loadStore() throws -> DurableLedgerStore {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return DurableLedgerStore() }
        do { return try JSONDecoder().decode(DurableLedgerStore.self, from: Data(contentsOf: storeURL)) }
        catch { throw DurableLedgerError.corruptStore }
    }

    private func persist(_ store: DurableLedgerStore) throws {
        let data = try JSONEncoder().encode(store)
        let temporary = storeURL.deletingLastPathComponent().appendingPathComponent(".\(storeURL.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: [.atomic])
        if FileManager.default.fileExists(atPath: storeURL.path) {
            _ = try FileManager.default.replaceItemAt(storeURL, withItemAt: temporary, backupItemName: nil, options: [])
        } else {
            try FileManager.default.moveItem(at: temporary, to: storeURL)
        }
    }
}
