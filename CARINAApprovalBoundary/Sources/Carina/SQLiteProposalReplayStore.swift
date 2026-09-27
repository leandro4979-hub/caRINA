import CSQLite
import Foundation

public final class SQLiteProposalReplayStore: ProposalReplayChecking, @unchecked Sendable {
    public let databaseURL: URL

    private let lock = NSLock()
    private var database: OpaquePointer?

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL

        let directoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        if !FileManager.default.fileExists(atPath: databaseURL.path) {
            guard FileManager.default.createFile(
                atPath: databaseURL.path,
                contents: Data(),
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw ApprovalStateStoreError.databaseUnavailable
            }
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: databaseURL.path
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
            try Self.execute(
                """
                CREATE TABLE IF NOT EXISTS proposal_replay_reservations (
                    proposal_id TEXT PRIMARY KEY,
                    digest TEXT NOT NULL UNIQUE,
                    created_at REAL NOT NULL
                )
                """,
                database: handle
            )
        } catch {
            sqlite3_close(handle)
            throw error
        }

        database = handle
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func reserve(
        proposalID: UUID,
        digest: String
    ) throws -> ProposalReplayReservation {
        lock.lock()
        defer { lock.unlock() }

        guard let database else {
            throw ApprovalStateStoreError.databaseUnavailable
        }

        try Self.execute("BEGIN IMMEDIATE", database: database)
        do {
            if try Self.exists(
                sql: "SELECT 1 FROM proposal_replay_reservations WHERE proposal_id = ? LIMIT 1",
                value: proposalID.uuidString.lowercased(),
                database: database
            ) {
                try Self.execute("ROLLBACK", database: database)
                return .proposalAlreadyReserved
            }

            if try Self.exists(
                sql: "SELECT 1 FROM proposal_replay_reservations WHERE digest = ? LIMIT 1",
                value: digest,
                database: database
            ) {
                try Self.execute("ROLLBACK", database: database)
                return .digestAlreadyReserved
            }

            try Self.insert(
                proposalID: proposalID.uuidString.lowercased(),
                digest: digest,
                database: database
            )
            try Self.execute("COMMIT", database: database)
            return .reserved
        } catch {
            try? Self.execute("ROLLBACK", database: database)
            throw error
        }
    }

    private static func exists(
        sql: String,
        value: String,
        database: OpaquePointer
    ) throws -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        guard value.withCString({
            sqlite3_bind_text(
                statement,
                1,
                $0,
                -1,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }) == SQLITE_OK else {
            throw databaseError(database)
        }

        let step = sqlite3_step(statement)
        if step == SQLITE_ROW { return true }
        if step == SQLITE_DONE { return false }
        throw databaseError(database)
    }

    private static func insert(
        proposalID: String,
        digest: String,
        database: OpaquePointer
    ) throws {
        let sql = """
        INSERT INTO proposal_replay_reservations
            (proposal_id, digest, created_at)
        VALUES (?, ?, ?)
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError(database)
        }
        defer { sqlite3_finalize(statement) }

        let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard proposalID.withCString({
            sqlite3_bind_text(statement, 1, $0, -1, destructor)
        }) == SQLITE_OK,
        digest.withCString({
            sqlite3_bind_text(statement, 2, $0, -1, destructor)
        }) == SQLITE_OK,
        sqlite3_bind_double(
            statement,
            3,
            Date().timeIntervalSince1970
        ) == SQLITE_OK else {
            throw databaseError(database)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw databaseError(database)
        }
    }

    private static func execute(
        _ sql: String,
        database: OpaquePointer
    ) throws {
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            let detail = message.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            if let message { sqlite3_free(message) }
            throw ApprovalStateStoreError.databaseFailure(detail)
        }
        if let message { sqlite3_free(message) }
    }

    private static func databaseError(
        _ database: OpaquePointer
    ) -> ApprovalStateStoreError {
        guard let message = sqlite3_errmsg(database) else {
            return .databaseUnavailable
        }
        return .databaseFailure(String(cString: message))
    }
}
