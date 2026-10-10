import XCTest
@testable import Token_Monitor

final class UsageRepositoryTests: XCTestCase {
    func testRepeatedImportIsIdempotentAndChangedAggregateReplacesExistingRow() async throws {
        let repository = try UsageRepository(inMemory: true)
        let initial = usage(input: 10)
        let changed = usage(input: 25)

        try await repository.importSource(.succeeded(source: .hermes, records: [initial], titles: [:]))
        try await repository.importSource(.succeeded(source: .hermes, records: [initial], titles: [:]))
        var cached = try await repository.load()
        XCTAssertEqual(cached.snapshot.records.count, 1)
        XCTAssertEqual(cached.snapshot.records.first?.inputTokens, 10)

        try await repository.importSource(.succeeded(source: .hermes, records: [changed], titles: [:]))
        cached = try await repository.load()
        XCTAssertEqual(cached.snapshot.records.count, 1)
        XCTAssertEqual(cached.snapshot.records.first?.inputTokens, 25)
    }

    func testMissingSourceRetainsLastKnownRecordsAndMarksFreshness() async throws {
        let repository = try UsageRepository(inMemory: true)
        let record = usage(input: 10)

        try await repository.importSource(.succeeded(source: .zcode, records: [record], titles: [:]))
        try await repository.importSource(.missing(source: .zcode))
        let cached = try await repository.load()

        XCTAssertEqual(cached.snapshot.records.count, 1)
        XCTAssertEqual(cached.sourceStatuses.first?.status, .missing)
        XCTAssertNotNil(cached.sourceStatuses.first?.lastSuccessfulRefresh)
    }

    func testRebuildClearsOnlyDerivedCache() async throws {
        let repository = try UsageRepository(inMemory: true)
        try await repository.importSource(.succeeded(source: .claude, records: [usage(input: 1)], titles: [:]))

        try await repository.rebuildCache()
        let cached = try await repository.load()

        XCTAssertTrue(cached.snapshot.records.isEmpty)
        XCTAssertTrue(cached.sourceStatuses.isEmpty)
    }

    private func usage(input: Int) -> TokenUsage {
        TokenUsage(timestamp: Date(timeIntervalSince1970: 1_700_000_000), model: "model",
                   inputTokens: input, outputTokens: 2, cacheCreationTokens: 0, cacheReadTokens: 0,
                   sessionId: "session", projectPath: "/tmp/project", source: .hermes,
                   provider: BillingProvider(rawValue: "anthropic"), providerRawValue: "anthropic",
                   providerProvenance: .sourceMetadata, granularity: .lifetimeSessionModelAggregate)
    }
}
