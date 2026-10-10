import Foundation
import SQLite3

/// Reads Hermes token usage from the local SQLite database that the Hermes
/// CLI maintains at `~/.hermes/state.db`.
///
/// Hermes aggregates usage per `(session_id, model, billing_provider)` in the
/// `session_model_usage` table, and stores the working directory + title of
/// each session in the `sessions` table. This parser mirrors the shape of
/// `ZCodeTokenParser` so all three sources (Claude, ZCode, Hermes) can be
/// merged transparently by `TokenService`.
///
/// The database is opened **read-only**, so concurrent writes from a running
/// Hermes process are safe (SQLite WAL handles readers and writers concurrently).
actor HermesTokenParser: TokenUsageParser {
    let source: TokenSource = .hermes
    private let dbPath: String

    init(dbPath: String = NSHomeDirectory() + "/.hermes/state.db") {
        self.dbPath = dbPath
    }

    func parseAllTokenUsage() async -> [TokenUsage] {
        // Bail out silently when Hermes isn't installed / hasn't created a DB.
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return []
        }

        var sessions: [String: (cwd: String, title: String?)] = [:]
        var usages: [TokenUsage] = []

        guard let db = openReadOnly() else {
            return []
        }
        defer { sqlite3_close(db) }

        // Apply a short busy timeout in case Hermes is mid-write.
        sqlite3_busy_timeout(db, 2_000)

        loadSessionMetadata(into: &sessions, db: db)
        loadModelUsage(into: &usages, sessions: sessions, db: db)

        return usages
    }

    // MARK: - Helpers

    /// Opens the database read-only via a `file:` URI so we never risk
    /// modifying Hermes's live data.
    private func openReadOnly() -> OpaquePointer? {
        let escaped = dbPath.replacingOccurrences(of: "?", with: "%3F")
        let uri = "file:\(escaped)?mode=ro"
        var db: OpaquePointer?
        // SQLITE_OPEN_READONLY | SQLITE_OPEN_URI → read-only + honor URI params.
        let result = sqlite3_open_v2(
            uri,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil
        )
        guard result == SQLITE_OK, db != nil else {
            return nil
        }
        return db
    }

    /// Loads `id → (cwd, title)` from the `sessions` table.
    private func loadSessionMetadata(
        into sessions: inout [String: (cwd: String, title: String?)],
        db: OpaquePointer
    ) {
        let sql = "SELECT id, cwd, title FROM sessions;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else {
            return
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idC)
            let cwd = textColumn(stmt, 1) ?? ""
            let title = textColumn(stmt, 2)
            sessions[id] = (cwd, title)
        }
    }

    /// Streams aggregated model usage rows and appends a `TokenUsage` per row.
    private func loadModelUsage(
        into usages: inout [TokenUsage],
        sessions: [String: (cwd: String, title: String?)],
        db: OpaquePointer
    ) {
        // Hermes has no per-request status column; every row is a finalized
        // aggregate, so no `WHERE status = ...` filter is needed.
        let sql = """
            SELECT session_id, model, billing_provider, input_tokens, output_tokens,
                   cache_read_tokens, cache_write_tokens, reasoning_tokens,
                   last_seen
            FROM session_model_usage;
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else {
            return
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sessionIdC = sqlite3_column_text(stmt, 0) else { continue }
            let sessionId = String(cString: sessionIdC)

            let model = textColumn(stmt, 1) ?? "unknown"
            let providerRawValue = textColumn(stmt, 2)
            let provider = BillingProvider(rawValue: providerRawValue)

            let inputTokens = intColumn(stmt, 3)
            let outputTokens = intColumn(stmt, 4)
            let cacheRead = intColumn(stmt, 5)
            let cacheWrite = intColumn(stmt, 6)
            let reasoningTokens = intColumn(stmt, 7)

            // `last_seen` is epoch seconds (Hermes), not milliseconds — unlike
            // ZCode. Use the most recent activity as the row's timestamp.
            let lastSeen = sqlite3_column_double(stmt, 8)
            let timestamp = Date(timeIntervalSince1970: lastSeen)

            // Reasoning tokens are billed as output, so fold them in to keep
            // our totals aligned with the provider's computed total.
            let projectPath = sessions[sessionId]?.cwd ?? ""

            usages.append(TokenUsage(
                timestamp: timestamp,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens + reasoningTokens,
                cacheCreationTokens: cacheWrite,
                cacheReadTokens: cacheRead,
                sessionId: sessionId,
                projectPath: projectPath,
                source: .hermes,
                provider: provider,
                providerRawValue: providerRawValue,
                providerProvenance: providerRawValue == nil ? .unavailable : .sourceMetadata,
                granularity: .lifetimeSessionModelAggregate
            ))
        }
    }

    /// Safely reads a TEXT column as a Swift `String` (handles NULL + UTF-8).
    private func textColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    /// Reads an INTEGER column as a non-negative `Int`, treating NULL as 0.
    private func intColumn(_ stmt: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }
}
