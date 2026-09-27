import Foundation
import SQLite3

// Accessed from MonitorController's main actor; bounded pages keep reads small.
public final class HistoryStore {
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            let error = databaseError()
            sqlite3_close(database)
            database = nil
            throw error
        }
        sqlite3_busy_timeout(database, 2000)
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("CREATE TABLE IF NOT EXISTS requests (sequence INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)")
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    @discardableResult
    public func append(_ record: RequestRecord) throws -> Int64 {
        let payload = String(decoding: try encoder.encode(record), as: UTF8.self)
        let statement = try prepare("INSERT INTO requests (payload) VALUES (?)")
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, payload, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
        return sqlite3_last_insert_rowid(database)
    }

    public func update(_ record: RequestRecord, sequence: Int64) throws {
        let payload = String(decoding: try encoder.encode(record), as: UTF8.self)
        let statement = try prepare("UPDATE requests SET payload = ? WHERE sequence = ?")
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, payload, -1, transient) == SQLITE_OK,
              sqlite3_bind_int64(statement, 2, sequence) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
        guard sqlite3_changes(database) == 1 else { throw ValidationError.message("找不到要更新的请求记录。") }
    }

    public func recoverInterruptedRequests() throws {
        // payload 由本类 JSONEncoder 生成。只解码有 running 标记的新记录，兼容旧表结构。
        let statement = try prepare("SELECT sequence, payload FROM requests WHERE payload LIKE '%\"phase\":\"running\"%'")
        var interrupted: [(Int64, RequestRecord)] = []
        do {
            defer { sqlite3_finalize(statement) }
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 1) else { throw databaseError() }
                var record = try decoder.decode(RequestRecord.self, from: Data(String(cString: bytes).utf8))
                guard record.isInFlight else { continue }
                record.phase = .interrupted
                if record.outcome == .pending { record.outcome = .cancelled }
                record.detail += " · 上次运行中断，耗时为最后已知值"
                interrupted.append((sqlite3_column_int64(statement, 0), record))
            }
        }
        for (sequence, record) in interrupted { try update(record, sequence: sequence) }
    }

    public func count() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM requests")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    public func page(limit: Int = 200, offset: Int = 0) throws -> [RequestRecord] {
        let statement = try prepare("SELECT payload FROM requests ORDER BY sequence DESC LIMIT ? OFFSET ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(max(1, limit)))
        sqlite3_bind_int64(statement, 2, Int64(max(0, offset)))
        var records: [RequestRecord] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return records }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw databaseError() }
            records.append(try decoder.decode(RequestRecord.self, from: Data(String(cString: bytes).utf8)))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
    }

    private func databaseError() -> Error {
        let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
        return ValidationError.message("历史记录数据库错误：\(detail)")
    }
}
