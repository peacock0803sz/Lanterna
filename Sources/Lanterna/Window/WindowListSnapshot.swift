import Foundation

/// The result of one pass over every listable application.
///
/// Nothing is kept between passes: the list is gathered when the panel is about
/// to be shown and lives no longer than the process.
struct WindowListSnapshot {
    /// An application that answered with nothing usable. Named in the
    /// diagnostics line so a missing application is explained rather than
    /// silently absent.
    struct SkippedApplication {
        let name: String
        let reason: ReadFailure
    }

    /// Grouped by application in process-identifier order, and within an
    /// application in window-id order.
    let items: [WindowItem]
    /// Every application the pass looked at, including the skipped ones.
    let applicationCount: Int
    /// Entry to assembled list, covering everything the panel waited for.
    let gatheringDuration: Duration
    let skipped: [SkippedApplication]
    let droppedWithoutID: Int

    /// `assert` rather than `precondition`: a duplicated id is loud in debug
    /// builds and under test, but a doubled row must never take the panel
    /// down in release.
    init(
        items: [WindowItem],
        applicationCount: Int,
        gatheringDuration: Duration,
        skipped: [SkippedApplication],
        droppedWithoutID: Int
    ) {
        assert(Set(items.map(\.id)).count == items.count, "window ids must be unique")
        self.items = items
        self.applicationCount = applicationCount
        self.gatheringDuration = gatheringDuration
        self.skipped = skipped
        self.droppedWithoutID = droppedWithoutID
    }

    /// The one line written after a pass. Counts, timings and skipped
    /// application names only — never a window title.
    var summaryLine: String {
        var line = "listed \(items.count) windows from \(applicationCount) applications "
            + "in \(Diagnostics.millisecondsText(gatheringDuration)) ms"
        if !skipped.isEmpty {
            let reasons = skipped.map { "\($0.name) (\(Self.text(for: $0.reason)))" }
            line += "; skipped " + reasons.joined(separator: ", ")
        }
        if droppedWithoutID > 0 {
            line += "; dropped \(droppedWithoutID) elements without a window id"
        }
        return line
    }

    private static func text(for reason: ReadFailure) -> String {
        switch reason {
        case .timedOut:
            "timed out"
        case .permissionMissing:
            "permission missing"
        case .malformedAnswer:
            "malformed answer"
        case let .unavailable(error):
            "error \(error.rawValue)"
        }
    }
}
