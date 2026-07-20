import Foundation

/// A source of token-usage records (Claude JSONL, ZCode SQLite, Hermes SQLite, …).
///
/// Concrete parsers are `actor`s, so the protocol is `Sendable` and instances
/// can be stored on the `@MainActor`-isolated `TokenService` and fanned out
/// across a `TaskGroup`.
protocol TokenUsageParser: Sendable {
    /// All token-usage records this source can produce.
    func parseAllTokenUsage() async -> [TokenUsage]

    /// Mapping of `sessionId` → human-readable title, for sources that store
    /// titles out-of-band from the usage rows. Sources without titles return `[:]`.
    func parseSessionTitles() async -> [String: String]
}

/// Default "no titles" implementation — used by the SQLite-backed parsers,
/// which already embed the working directory in each usage row.
extension TokenUsageParser {
    func parseSessionTitles() async -> [String: String] {
        [:]
    }
}
