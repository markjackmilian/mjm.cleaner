import SQLite3

struct SQLiteError: Error, Equatable, Sendable, CustomStringConvertible {
    let code: Int32
    let description: String
}

enum SQLiteValue: Equatable, Sendable {
    case integer(Int64)
    case text(String)
    case null

    var integer: Int64? {
        if case .integer(let value) = self { value } else { nil }
    }

    var text: String? {
        if case .text(let value) = self { value } else { nil }
    }
}

/// `SQLITE_TRANSIENT` non è importato in Swift: chiede a SQLite di copiare subito il testo legato.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Wrapper minimo sulla libreria SQLite di sistema: apertura, SQL diretto, statement preparati con
/// parametri posizionali. Una connessione per operazione, come in C#: due tabelle non giustificano
/// un ORM né una connessione condivisa.
final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(path: String) throws {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 fallita"
            sqlite3_close(database)
            throw SQLiteError(code: status, description: message)
        }
        handle = database
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw error(status) }
    }

    /// Esegue `sql` legando i parametri nell'ordine e restituisce tutte le righe.
    @discardableResult
    func query(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw error(prepared) }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .integer(let number): status = sqlite3_bind_int64(statement, index, number)
            case .text(let text): status = sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case .null: status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else { throw error(status) }
        }

        var rows: [[SQLiteValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { throw error(step) }

            rows.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER:
                    return .integer(sqlite3_column_int64(statement, column))
                case SQLITE_NULL:
                    return .null
                default:
                    return .text(sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "")
                }
            })
        }
    }

    var lastInsertRowId: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    private func error(_ status: Int32) -> SQLiteError {
        SQLiteError(code: status, description: String(cString: sqlite3_errmsg(handle)))
    }
}
