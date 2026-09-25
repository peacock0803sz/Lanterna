@testable import Lanterna
import Testing

/// The filtering tail on commit and cancel lines.
///
/// A file of its own for the reason `PanelPresenterCommitTests` is one: the
/// suite pinning the exit wordings is long enough that adding to it would
/// put it over the file limit.
///
/// The wording of the tail is pinned here rather than where the summary is
/// handed over, so a reword shows up as a failure in the file that owns the
/// wording.
struct FilterDiagnosticsTests {
    /// The same wording the exit tests pin, with a filtering tail behind it.
    private static func measurement(
        _ outcome: PanelExitMeasurement.Outcome,
        by trigger: PanelExitMeasurement.Trigger = .commandRelease,
        filterSummary: FilterLogSummary? = nil
    ) -> PanelExitMeasurement {
        PanelExitMeasurement(
            outcome: outcome,
            trigger: trigger,
            elapsed: .microseconds(4800),
            filterSummary: filterSummary
        )
    }

    /// Stands in for whichever window was taken.
    private static let someWindow = WindowItem.Identifier(windowID: 42)

    private static func committed(appName: String, displayTitle: String) -> PanelExitMeasurement.Outcome {
        .committed(appName: appName, displayTitle: displayTitle, id: someWindow)
    }

    /// A commit after narrowing carries the query and the counts on its
    /// tail, and nothing else changes about the line.
    @Test func aFilteredCommitCarriesTheQueryAndTheCounts() {
        let row = Self.committed(appName: "Safari", displayTitle: "Release notes")
        let summary = FilterLogSummary(query: "saf", matchedCount: 2, totalCount: 12)
        #expect(
            Self.measurement(row, filterSummary: summary).summaryLine
                == "committed Safari — Release notes (window 42) 4.8 ms after "
                + "Command was released; filter \"saf\" (2 of 12)"
        )
    }

    /// An empty query writes no tail: the line reads as it always did.
    @Test func anEmptyQueryWritesNoTail() {
        let row = Self.committed(appName: "Safari", displayTitle: "Release notes")
        let summary = FilterLogSummary(query: "", matchedCount: 12, totalCount: 12)
        #expect(
            Self.measurement(row, filterSummary: summary).summaryLine
                == "committed Safari — Release notes (window 42) 4.8 ms after Command was released"
        )
        #expect(
            Self.measurement(.cancelled, by: .cancelKey(.escape), filterSummary: summary).summaryLine
                == "cancelled 4.8 ms after Escape"
        )
    }

    /// A cancel after narrowing carries the same tail as a commit.
    @Test func aFilteredCancelCarriesTheSameTail() {
        let summary = FilterLogSummary(query: "saf", matchedCount: 2, totalCount: 12)
        #expect(
            Self.measurement(.cancelled, by: .cancelKey(.escape), filterSummary: summary).summaryLine
                == "cancelled 4.8 ms after Escape; filter \"saf\" (2 of 12)"
        )
    }

    /// A query that would split the line is flattened, and quotes are
    /// dropped rather than escaped.
    @Test func aQueryThatWouldSplitTheLineIsFlattened() {
        let row = Self.committed(appName: "Safari", displayTitle: "Release notes")
        let summary = FilterLogSummary(query: "a\nb\"c", matchedCount: 1, totalCount: 12)
        let line = Self.measurement(row, filterSummary: summary).summaryLine
        #expect(line.hasSuffix("; filter \"a bc\" (1 of 12)"))
        #expect(line.filter { $0.isNewline }.isEmpty)
    }
}
