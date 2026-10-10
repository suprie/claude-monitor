import XCTest
import SQLite3
@testable import Token_Monitor

final class ProviderParserTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryURLs { try? FileManager.default.removeItem(at: url) }
        temporaryURLs.removeAll()
    }

    func testZCodePreservesProviderMetadataWithoutInferringFromModel() async throws {
        let dbURL = try makeDatabase()
        try execute("""
            CREATE TABLE session (id TEXT, title TEXT, directory TEXT);
            CREATE TABLE model_usage (session_id TEXT, started_at INTEGER, provider_id TEXT, model_id TEXT,
                input_tokens INTEGER, output_tokens INTEGER, reasoning_tokens INTEGER,
                cache_creation_input_tokens INTEGER, cache_read_input_tokens INTEGER, status TEXT);
            INSERT INTO session VALUES ('z-session', 'title', '/tmp/project');
            INSERT INTO model_usage VALUES ('z-session', 1791626400000, 'openai', 'mystery-model', 10, 20, 0, 0, 0, 'completed');
            """, at: dbURL)

        let usages = await ZCodeTokenParser(dbPath: dbURL.path).parseAllTokenUsage()
        let usage = try XCTUnwrap(usages.first)

        XCTAssertEqual(usage.provider, BillingProvider(rawValue: "openai"))
        XCTAssertEqual(usage.providerRawValue, "openai")
        XCTAssertEqual(usage.providerProvenance, .sourceMetadata)
        XCTAssertEqual(usage.granularity, .requestEvent)
        XCTAssertEqual(usage.model, "mystery-model")
    }

    func testHermesPreservesMultipleProvidersAsLifetimeAggregates() async throws {
        let dbURL = try makeDatabase()
        try execute("""
            CREATE TABLE sessions (id TEXT, cwd TEXT, title TEXT);
            CREATE TABLE session_model_usage (session_id TEXT, model TEXT, billing_provider TEXT,
                input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER,
                cache_write_tokens INTEGER, reasoning_tokens INTEGER, last_seen REAL);
            INSERT INTO sessions VALUES ('h-session', '/tmp/project', 'title');
            INSERT INTO session_model_usage VALUES ('h-session', 'model-a', 'anthropic', 10, 20, 0, 0, 0, 1791626400);
            INSERT INTO session_model_usage VALUES ('h-session', 'model-b', 'openai', 30, 40, 0, 0, 0, 1791626401);
            """, at: dbURL)

        let usages = await HermesTokenParser(dbPath: dbURL.path).parseAllTokenUsage()

        XCTAssertEqual(usages.map(\.provider).sorted { $0.rawValue < $1.rawValue }, [BillingProvider(rawValue: "anthropic"), BillingProvider(rawValue: "openai")])
        XCTAssertTrue(usages.allSatisfy { $0.providerProvenance == .sourceMetadata })
        XCTAssertTrue(usages.allSatisfy { $0.granularity == .lifetimeSessionModelAggregate })
    }

    private func makeDatabase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProviderParserTests-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_close(db)
        temporaryURLs.append(url)
        return url
    }

    private func execute(_ sql: String, at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw NSError(domain: "ProviderParserTests", code: 1)
        }
        defer { sqlite3_close(db) }
        var error: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(error)
            throw NSError(domain: "ProviderParserTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
