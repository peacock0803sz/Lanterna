import ApplicationServices
@testable import Lanterna
import Testing

/// What one element of an application's window list becomes. The order of the
/// checks is the point: excluding before counting a missing id is what keeps
/// the Finder desktop out of the dropped tally.
struct ApplicationWindowReaderTests {
    private typealias Reader = AXApplicationWindowReader

    @Test func aStandardWindowBecomesARecord() {
        let outcome = Reader.outcome(
            role: kAXWindowRole,
            subrole: kAXStandardWindowSubrole,
            title: "Downloads",
            isMinimized: false,
            windowID: 42
        )
        #expect(outcome == .record(
            WindowRecord(windowID: 42, title: "Downloads", kind: .standard, isMinimized: false)
        ))
    }

    @Test(arguments: [
        (kAXDialogSubrole, WindowKind.dialog),
        (kAXSystemDialogSubrole, WindowKind.dialog),
        (kAXUnknownSubrole, WindowKind.undetermined),
        ("AXSomethingNewInTheNextRelease", WindowKind.undetermined),
    ])
    func aListedElementCarriesItsKind(subrole: String, kind: WindowKind) {
        let outcome = Reader.outcome(
            role: kAXWindowRole,
            subrole: subrole,
            title: "Open",
            isMinimized: false,
            windowID: 42
        )
        #expect(outcome == .record(
            WindowRecord(windowID: 42, title: "Open", kind: kind, isMinimized: false)
        ))
    }

    /// The Finder desktop: not a window, and it has no id either. It must be
    /// excluded rather than reported as a window that was lost.
    @Test func anElementThatIsNotAWindowIsExcludedRatherThanDropped() {
        let outcome = Reader.outcome(
            role: kAXScrollAreaRole,
            subrole: nil,
            title: "",
            isMinimized: false,
            windowID: nil
        )
        #expect(outcome == .excluded)
    }

    @Test(arguments: [kAXFloatingWindowSubrole, kAXSystemFloatingWindowSubrole])
    func anAuxiliaryPanelIsExcludedEvenWithAnID(subrole: String) {
        let outcome = Reader.outcome(
            role: kAXWindowRole,
            subrole: subrole,
            title: "Fonts",
            isMinimized: false,
            windowID: 42
        )
        #expect(outcome == .excluded)
    }

    /// Identity comes from the window id, so a window without one cannot become
    /// a row — but it is counted, so the loss is visible in the diagnostics.
    @Test(arguments: [nil, CGWindowID(0)])
    func aWindowWithoutAnIDIsCountedAsDropped(windowID: CGWindowID?) {
        let outcome = Reader.outcome(
            role: kAXWindowRole,
            subrole: kAXStandardWindowSubrole,
            title: "Downloads",
            isMinimized: false,
            windowID: windowID
        )
        #expect(outcome == .droppedWithoutID)
    }

    @Test func aMinimizedWindowKeepsItsState() {
        let outcome = Reader.outcome(
            role: kAXWindowRole,
            subrole: kAXStandardWindowSubrole,
            title: "Downloads",
            isMinimized: true,
            windowID: 42
        )
        #expect(outcome == .record(
            WindowRecord(windowID: 42, title: "Downloads", kind: .standard, isMinimized: true)
        ))
    }

    /// A terminal can report a single space as its title. The record keeps it
    /// verbatim; deciding what to draw is the row's job.
    @Test(arguments: ["", " ", "\n"])
    func aBlankTitleIsKeptAsReported(title: String) {
        let outcome = Reader.outcome(
            role: kAXWindowRole,
            subrole: kAXStandardWindowSubrole,
            title: title,
            isMinimized: false,
            windowID: 42
        )
        #expect(outcome == .record(
            WindowRecord(windowID: 42, title: title, kind: .standard, isMinimized: false)
        ))
    }
}

/// How long an application is given before its windows are abandoned.
struct ReadBudgetTests {
    private let budget = ReadBudget(startedAt: .now)

    @Test(arguments: [Duration.zero, .milliseconds(300), .milliseconds(999)])
    func timeStillLeft(elapsed: Duration) {
        #expect(!budget.isExpired(at: budget.startedAt.advanced(by: elapsed)))
    }

    @Test(arguments: [Duration.seconds(1), .milliseconds(1001), .seconds(5)])
    func timeSpent(elapsed: Duration) {
        #expect(budget.isExpired(at: budget.startedAt.advanced(by: elapsed)))
    }
}
