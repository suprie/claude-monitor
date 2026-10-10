import XCTest
@testable import Token_Monitor

final class CodexTokenParserTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexTokenParserTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "codex-rollout-fixture", withExtension: "jsonl")
        )
        try FileManager.default.copyItem(
            at: fixture,
            to: tempDir.appendingPathComponent("rollout-test.jsonl")
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    func testParsesOneTokenUsageRecordPerTokenCountEvent() async throws {
        let parser = CodexTokenParser(sessionsPath: tempDir.path)
        let usages = await parser.parseAllTokenUsage()

        XCTAssertEqual(usages.count, 2)
    }

    func testFirstTurnUsesModelAndSessionInEffectAtThatPoint() async throws {
        let parser = CodexTokenParser(sessionsPath: tempDir.path)
        let usages = await parser.parseAllTokenUsage()

        let first = try XCTUnwrap(usages.first)
        XCTAssertEqual(first.sessionId, "01997bf8-c02f-7810-973b-d12f80cc066a")
        XCTAssertEqual(first.projectPath, "/Users/example/Workspace/demo-project")
        XCTAssertEqual(first.model, "gpt-5-codex")
        XCTAssertEqual(first.source, .codex)
        XCTAssertEqual(first.inputTokens, 2967)
        XCTAssertEqual(first.cacheReadTokens, 2560)
        XCTAssertEqual(first.cacheCreationTokens, 0)
        // outputTokens folds reasoning_output_tokens into output, matching ZCodeTokenParser.
        XCTAssertEqual(first.outputTokens, 136 + 64)
    }

    func testSecondTurnPicksUpModelFromLaterTurnContextAndUsesLastNotTotalUsage() async throws {
        let parser = CodexTokenParser(sessionsPath: tempDir.path)
        let usages = await parser.parseAllTokenUsage()

        let second = try XCTUnwrap(usages.last)
        XCTAssertEqual(second.model, "gpt-5.1-codex-mini")
        // Fixture's last_token_usage (1200/340/98/40) differs from total_token_usage
        // (4310/2900/98/40) — parser must use the per-turn delta, not the cumulative total.
        XCTAssertEqual(second.inputTokens, 1200)
        XCTAssertEqual(second.cacheReadTokens, 340)
        XCTAssertEqual(second.outputTokens, 98 + 40)
    }
}
