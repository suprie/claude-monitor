import Foundation
import SQLite3

/// Reads ZCode token usage from the local SQLite database that the ZCode CLI
/// maintains at `~/.zcode/cli/db/db.sqlite`.
///
/// ZCode records one row per model request in the `model_usage` table (with
/// per-request token counts linked to a `session_id`) and stores the human
/// title + working directory of each session in the `session` table. This
/// parser mirrors the shape of `TokenParser` so the two sources can be merged
/// transparently by `TokenService`.
///
/// The database is opened **read-only**, so concurrent writes from a running
/// ZCode process are safe (SQLite WAL handles readers and writers concurrently).
actor ZCodeTokenParser: TokenUsageParser {
    private let dbPath: String

    init(dbPath: String = NSHomeDirectory() + "/.zcode/cli/db/db.sqlite") {
        self.dbPath = dbPath
    }

    func parseAllTokenUsage() async -> [TokenUsage] {
        // Bail out silently when ZCode isn't installed / hasn't created a DB.
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return []
        }

        var titles: [String: (title: String, directory: String)] = [:]
        var usages: [TokenUsage] = []

        guard let db = openReadOnly() else {
            return []
        }
        defer { sqlite3_close(db) }

        // Apply a short busy timeout in case ZCode is mid-write.
        sqlite3_busy_timeout(db, 2_000)

        loadSessionMetadata(into: &titles, db: db)
        loadModelUsage(into: &usages, titles: titles, db: db)

        return usages
    }
    
    func parseSessionTitles() async -> [SessionKey : String] {
        // Bail out silently when ZCode isn't installed / hasn't created a DB.
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return [:]
        }
        
        var titles: [SessionKey: String] = [:]
        
        guard let db = openReadOnly() else {
            return [:]
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)
        let sql = "SELECT id, title FROM session;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else {
            return [:]
        }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idC)
            let title = textColumn(stmt, 1) ?? ""
            titles[SessionKey(source: .zcode, sessionId: id)] = title
        }
        return titles
    }

    // MARK: - Helpers

    /// Opens the database read-only via a `file:` URI so we never risk
    /// modifying ZCode's live data.
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

    /// Loads `id → (title, directory)` from the `session` table.
    private func loadSessionMetadata(
        into titles: inout [String: (title: String, directory: String)],
        db: OpaquePointer
    ) {
        let sql = "SELECT id, title, directory FROM session;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt = stmt else {
            return
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idC)
            let title = textColumn(stmt, 1) ?? ""
            let directory = textColumn(stmt, 2) ?? ""
            titles[id] = (title, directory)
        }
    }

    /// Streams completed model requests and appends a `TokenUsage` per row.
    private func loadModelUsage(
        into usages: inout [TokenUsage],
        titles: [String: (title: String, directory: String)],
        db: OpaquePointer
    ) {
        // Only count completed requests, matching how Claude excludes
        // cancelled/errored turns.
        let sql = """
            SELECT session_id, started_at, provider_id, model_id,
                   input_tokens, output_tokens, reasoning_tokens,
                   cache_creation_input_tokens, cache_read_input_tokens
            FROM model_usage
            WHERE status = 'completed';
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

            // started_at is epoch milliseconds.
            let startedAtMs = sqlite3_column_int64(stmt, 1)
            let timestamp = Date(timeIntervalSince1970: TimeInterval(startedAtMs) / 1000.0)

            // Model id is the most specific identifier available; fall back to
            // the provider id if the row lacks one.
            let providerRawValue = textColumn(stmt, 2)
            let provider = BillingProvider(rawValue: providerRawValue)
            let modelId = textColumn(stmt, 3) ?? "unknown"

            let inputTokens = intColumn(stmt, 4)
            let outputTokens = intColumn(stmt, 5)
            let reasoningTokens = intColumn(stmt, 6)
            let cacheCreation = intColumn(stmt, 7)
            let cacheRead = intColumn(stmt, 8)

            // Reasoning tokens are billed as output, so fold them in to keep
            // our totals aligned with the provider's computed total.
            let projectPath = titles[sessionId]?.directory ?? ""

            usages.append(TokenUsage(
                timestamp: timestamp,
                model: modelId,
                inputTokens: inputTokens,
                outputTokens: outputTokens + reasoningTokens,
                cacheCreationTokens: cacheCreation,
                cacheReadTokens: cacheRead,
                sessionId: sessionId,
                projectPath: projectPath,
                source: .zcode,
                provider: provider,
                providerRawValue: providerRawValue,
                providerProvenance: providerRawValue == nil ? .unavailable : .sourceMetadata,
                granularity: .requestEvent
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
