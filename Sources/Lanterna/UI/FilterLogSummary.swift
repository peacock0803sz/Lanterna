/// What a commit or cancel line says about the filtering that led to it.
///
/// The query, how many rows matched, and out of how many. Read at the exits
/// and travelling with the call, because the lines are written after the
/// closing and the filter itself is gone by then.
struct FilterLogSummary: Equatable, Sendable {
    let query: String
    let matchedCount: Int
    let totalCount: Int
}
