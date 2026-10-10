import XCTest
@testable import Token_Monitor

final class UsageQueryTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        now = date("2026-10-10T12:00:00Z")
    }

    func testPeriodsUseLocalCalendarAndExclusiveEnd() {
        let query = UsageQuery(calendar: calendar)
        let records = [
            usage("2026-10-10T00:00:00Z", session: "today", input: 1),
            usage("2026-10-11T00:00:00Z", session: "tomorrow", input: 10),
            usage("2026-10-01T00:00:00Z", session: "month", input: 100)
        ]
        let snapshot = UsageSnapshot(records: records)

        XCTAssertEqual(query.total(in: .today, from: snapshot, now: now), 1)
        XCTAssertEqual(query.total(in: .thisMonth, from: snapshot, now: now), 111)
        XCTAssertEqual(query.total(in: .allTime, from: snapshot, now: now), 111)
    }

    func testSameSessionIDFromDifferentSourcesStaysSeparate() {
        let query = UsageQuery(calendar: calendar)
        let records = [
            usage("2026-10-10T10:00:00Z", source: .claude, session: "same", input: 3),
            usage("2026-10-10T11:00:00Z", source: .codex, session: "same", input: 7)
        ]
        let sessions = query.sessions(in: .allTime, from: UsageSnapshot(records: records), now: now)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(Set(sessions.map(\.id)), ["claude:same", "codex:same"])
    }

    func testMixedModelSessionRetainsBothModels() throws {
        let query = UsageQuery(calendar: calendar)
        let records = [
            usage("2026-10-10T10:00:00Z", session: "mixed", model: "opus", input: 3),
            usage("2026-10-10T11:00:00Z", session: "mixed", model: "sonnet", output: 7)
        ]
        let sessions = query.sessions(in: .allTime, from: UsageSnapshot(records: records), now: now)
        let session = try XCTUnwrap(sessions.first)

        XCTAssertEqual(session.models.map(\.model), ["sonnet", "opus"])
        XCTAssertEqual(session.inputTokens, 3)
        XCTAssertEqual(session.outputTokens, 7)
    }

    func testTokenCategoriesAreNotRecombined() {
        let query = UsageQuery(calendar: calendar)
        let record = usage("2026-10-10T10:00:00Z", session: "categories", input: 2, output: 3, cacheCreate: 5, cacheRead: 7)

        XCTAssertEqual(query.total(in: .allTime, from: UsageSnapshot(records: [record]), now: now), 17)
    }

    private func usage(_ timestamp: String, source: TokenSource = .claude, session: String, model: String = "model", input: Int = 0, output: Int = 0, cacheCreate: Int = 0, cacheRead: Int = 0) -> TokenUsage {
        TokenUsage(timestamp: date(timestamp), model: model, inputTokens: input, outputTokens: output, cacheCreationTokens: cacheCreate, cacheReadTokens: cacheRead, sessionId: session, projectPath: "/tmp/project", source: source)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
