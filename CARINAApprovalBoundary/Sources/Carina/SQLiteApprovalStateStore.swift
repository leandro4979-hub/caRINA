import CSQLite
import Foundation

public enum ApprovalStateStoreError: Error, Sendable, Equatable {
    case databaseUnavailable
    case databaseFailure(String)
    case invalidStoredValue
}

public protocol ReplayStateStore: Sendable {
    func reserveReplay(
        _ key: ReplayKey,
        expiresAt: Date,
        now: Date
    ) async throws -> Bool
}

public protocol AuthorizationStateStore: Sendable {
    func insertChallenge(_ challenge: ApprovalChallenge) async throws
    func resolveChallenge(
        _ challenge: ApprovalChallenge,
        issuing token: AuthorizationToken?
    ) async throws -> Bool
    func consumeToken(_ token: AuthorizationToken) async throws -> AuthorizationToken?
}

public protocol IdempotencyStateStore: Sendable {
    func reserveIdempotencyKey(_ key: String) async throws -> Bool
    func containsIdempotencyKey(_ key: String) async throws -> Bool
}

/// Test/default storage. Production composition uses SQLiteApprovalStateStore.
public actor InMemoryApprovalStateStore:
    ReplayStateStore,
    AuthorizationStateStore,
    IdempotencyStateStore
{
    private var replayReservations: [ReplayKey: Date] = [:]
    private var challenges: [UUID: ApprovalChallenge] = [:]
    private var tokens: [UUID: AuthorizationToken] = [:]
    private var idempotencyKeys: Set<String> = []

    public init() {}

    public func reserveReplay(
        _ key: ReplayKey,
        expiresAt: Date,
        now: Date
    ) -> Bool {
        replayReservations = replayReservations.filter { $0.value > now }
        guard replayReservations[key] == nil else { return false }
        replayReservations[key] = expiresAt
        return true
    }

    public func insertChallenge(_ challenge: ApprovalChallenge) {
        challenges[challenge.id] = challenge
    }

    public func resolveChallenge(
        _ challenge: ApprovalChallenge,
        issuing token: AuthorizationToken?
    ) -> Bool {
        guard challenges[challenge.id] == challenge else { return false }
        challenges[challenge.id] = nil
        if let token { tokens[token.id] = token }
        return true
    }

    public func consumeToken(_ token: AuthorizationToken) -> AuthorizationToken? {
        let stored = tokens[token.id]
        tokens[token.id] = nil
        return stored
    }

    public func reserveIdempotencyKey(_ key: String) -> Bool {
        idempotencyKeys.insert(key).inserted
    }

    public func containsIdempotencyKey(_ key: String) -> Bool {
        idempotencyKeys.contains(key)
    }
}

/// Durable, privacy-minimized approval storage.
///
/// SQLite unique constraints and BEGIN IMMEDIATE transactions provide atomic
/// replay/idempotency reservation and compare-and-delete token consumption
/// across app restarts and cooperating processes on one host.
public actor SQLiteApprovalStateStore:
    ReplayStateStore,
    AuthorizationStateStore,
    IdempotencyStateStore
{
    public let databaseURL: URL
    private var database: OpaquePointer?

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw ApprovalStateStoreError.databaseUnavailable
        }
        do {
            guard sqlite3_busy_timeout(handle, 2_000) == SQLITE_OK else {
                throw Self.databaseError(handle)
            }
            try Self.bootstrap(handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }
        database = handle
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    private static func bootstrap(_ database: OpaquePointer) throws {
        let statements = [
            "PRAGMA journal_mode=WAL",
            "PRAGMA synchronous=FULL",
            "PRAGMA foreign_keys=ON",
            """
            CREATE TABLE IF NOT EXISTS replay_reservations (
                session_id TEXT NOT NULL,
                sequence TEXT NOT NULL,
                nonce TEXT NOT NULL,
                expires_at REAL NOT NULL,
                PRIMARY KEY (session_id, sequence, nonce)
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS approval_challenges (
                id TEXT PRIMARY KEY,
                fingerprint TEXT NOT NULL,
                expires_at REAL NOT NULL,
                target TEXT NOT NULL,
                correlation_id TEXT NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS authorization_tokens (
                id TEXT PRIMARY KEY,
                fingerprint TEXT NOT NULL,
                expires_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS idempotency_reservations (
                key TEXT PRIMARY KEY,
                created_at REAL NOT NULL
            )
            """
        ]

        for statement in statements {
            var message: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(
                database,
                statement,
                nil,
                nil,
                &message
            )
            guard result == SQLITE_OK else {
                let detail = message.map { String(cString: $0) }
                    ?? String(cString: sqlite3_errmsg(database))
                if let message { sqlite3_free(message) }
                throw ApprovalStateStoreError.databaseFailure(detail)
            }
            if let message { sqlite3_free(message) }
        }
    }

    private static func databaseError(
        _ database: OpaquePointer
    ) -> ApprovalStateStoreError {
        guard let message = sqlite3_errmsg(database) else {
            return .databaseUnavailable
        }
        return .databaseFailure(String(cString: message))
    }


    public func reserveReplay(
        _ key: ReplayKey,
        expiresAt: Date,
        now: Date
    ) throws -> Bool {
        try transaction {
            try execute(
                "DELETE FROM replay_reservations WHERE expires_at <= ?",
                bindings: [.double(now.timeIntervalSince1970)]
            )
            return try insert(
                """
                INSERT OR IGNORE INTO replay_reservations
                    (session_id, sequence, nonce, expires_at)
                VALUES (?, ?, ?, ?)
                """,
                bindings: [
                    .text(key.sessionID.uuidString.lowercased()),
                    .text(String(key.sequence)),
                    .text(key.nonce.uuidString.lowercased()),
                    .double(expiresAt.timeIntervalSince1970)
                ]
            )
        }
    }

    public func insertChallenge(_ challenge: ApprovalChallenge) throws {
        let inserted = try insert(
            """
            INSERT OR IGNORE INTO approval_challenges
                (id, fingerprint, expires_at, target, correlation_id)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(challenge.id.uuidString.lowercased()),
                .text(challenge.fingerprint),
                .double(challenge.expiresAt.timeIntervalSince1970),
                .text(challenge.target),
                .text(challenge.correlationID.uuidString.lowercased())
            ]
        )
        guard inserted else {
            throw ApprovalStateStoreError.databaseFailure("duplicate challenge")
        }
    }

    public func resolveChallenge(
        _ challenge: ApprovalChallenge,
        issuing token: AuthorizationToken?
    ) throws -> Bool {
        try transaction {
            guard let stored = try loadChallenge(id: challenge.id),
                  stored == challenge else {
                return false
            }
            try execute(
                "DELETE FROM approval_challenges WHERE id = ?",
                bindings: [.text(challenge.id.uuidString.lowercased())]
            )
            if let token {
                let inserted = try insert(
                    """
                    INSERT OR IGNORE INTO authorization_tokens
                        (id, fingerprint, expires_at)
                    VALUES (?, ?, ?)
                    """,
                    bindings: [
                        .text(token.id.uuidString.lowercased()),
                        .text(token.fingerprint),
                        .double(token.expiresAt.timeIntervalSince1970)
                    ]
                )
                guard inserted else {
                    throw ApprovalStateStoreError.databaseFailure("duplicate token")
                }
            }
            return true
        }
    }

    public func consumeToken(
        _ token: AuthorizationToken
    ) throws -> AuthorizationToken? {
        try transaction {
            guard let stored = try loadToken(id: token.id) else { return nil }
            try execute(
                "DELETE FROM authorization_tokens WHERE id = ?",
                bindings: [.text(token.id.uuidString.lowercased())]
            )
            return stored
        }
    }

    public func reserveIdempotencyKey(_ key: String) throws -> Bool {
        try insert(
            """
            INSERT OR IGNORE INTO idempotency_reservations (key, created_at)
            VALUES (?, ?)
            """,
            bindings: [.text(key), .double(Date().timeIntervalSince1970)]
        )
    }

    public func containsIdempotencyKey(_ key: String) throws -> Bool {
        try queryExists(
            "SELECT 1 FROM idempotency_reservations WHERE key = ? LIMIT 1",
            bindings: [.text(key)]
        )
    }

    private enum Binding {
        case text(String)
        case double(Double)
    }

    private func loadChallenge(id: UUID) throws -> ApprovalChallenge? {
        try withStatement(
            """
            SELECT fingerprint, expires_at, target, correlation_id
            FROM approval_challenges WHERE id = ?
            """
        ) { statement in
            try bind([.text(id.uuidString.lowercased())], to: statement)
            let step = sqlite3_step(statement)
            guard step == SQLITE_ROW else {
                if step == SQLITE_DONE { return nil }
                throw databaseError()
            }
            guard
                let fingerprint = columnText(statement, 0),
                let target = columnText(statement, 2),
                let correlationText = columnText(statement, 3),
                let correlationID = UUID(uuidString: correlationText)
            else {
                throw ApprovalStateStoreError.invalidStoredValue
            }
            return ApprovalChallenge(
                id: id,
                fingerprint: fingerprint,
                expiresAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                target: target,
                correlationID: correlationID
            )
        }
    }

    private func loadToken(id: UUID) throws -> AuthorizationToken? {
        try withStatement(
            "SELECT fingerprint, expires_at FROM authorization_tokens WHERE id = ?"
        ) { statement in
            try bind([.text(id.uuidString.lowercased())], to: statement)
            let step = sqlite3_step(statement)
            guard step == SQLITE_ROW else {
                if step == SQLITE_DONE { return nil }
                throw databaseError()
            }
            guard let fingerprint = columnText(statement, 0) else {
                throw ApprovalStateStoreError.invalidStoredValue
            }
            return AuthorizationToken(
                id: id,
                fingerprint: fingerprint,
                expiresAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            )
        }
    }

    private func queryExists(
        _ sql: String,
        bindings: [Binding]
    ) throws -> Bool {
        try withStatement(sql) { statement in
            try bind(bindings, to: statement)
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW { return true }
            if step == SQLITE_DONE { return false }
            throw databaseError()
        }
    }

    private func insert(
        _ sql: String,
        bindings: [Binding]
    ) throws -> Bool {
        try execute(sql, bindings: bindings)
        guard let database else {
            throw ApprovalStateStoreError.databaseUnavailable
        }
        return sqlite3_changes(database) == 1
    }

    private func execute(
        _ sql: String,
        bindings: [Binding] = []
    ) throws {
        try withStatement(sql) { statement in
            try bind(bindings, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError()
            }
        }
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func withStatement<T>(
        _ sql: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard let database else {
            throw ApprovalStateStoreError.databaseUnavailable
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError()
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(
        _ bindings: [Binding],
        to statement: OpaquePointer
    ) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case let .text(value):
                result = value.withCString {
                    sqlite3_bind_text(
                        statement,
                        index,
                        $0,
                        -1,
                        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                    )
                }
            case let .double(value):
                result = sqlite3_bind_double(statement, index, value)
            }
            guard result == SQLITE_OK else { throw databaseError() }
        }
    }

    private func columnText(
        _ statement: OpaquePointer,
        _ index: Int32
    ) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func databaseError() -> ApprovalStateStoreError {
        guard let database, let message = sqlite3_errmsg(database) else {
            return .databaseUnavailable
        }
        return .databaseFailure(String(cString: message))
    }
}
