import AppKit
@testable import Lanterna
import Testing

/// The summary line is what the quickstart greps to check the success criteria,
/// so its wording is pinned down here.
@MainActor
struct WindowListSnapshotTests {
    private func item(_ windowID: CGWindowID) -> WindowItem {
        WindowItem(
            id: WindowItem.Identifier(windowID: windowID),
            ownerProcessIdentifier: 0,
            appName: "Finder",
            bundleIdentifier: nil,
            windowTitle: "Downloads",
            kind: .standard,
            isMinimized: false,
            icon: NSImage()
        )
    }

    private func snapshot(
        windowCount: Int = 9,
        applicationCount: Int = 11,
        duration: Duration = .milliseconds(71.2),
        skipped: [WindowListSnapshot.SkippedApplication] = [],
        droppedWithoutID: Int = 0
    ) -> WindowListSnapshot {
        WindowListSnapshot(
            items: (0 ..< windowCount).map { item(CGWindowID($0)) },
            applicationCount: applicationCount,
            gatheringDuration: duration,
            skipped: skipped,
            droppedWithoutID: droppedWithoutID
        )
    }

    @Test func idsAreUniqueAcrossTheList() {
        #expect(Set(snapshot().items.map(\.id)).count == 9)
    }

    @Test func summaryReportsCountsAndDuration() {
        #expect(snapshot().summaryLine == "listed 9 windows from 11 applications in 71.2 ms")
    }

    /// An empty pass is reported in the same words, so the quickstart's grep
    /// finds the line whether or not anything was listed.
    @Test func summaryReportsAnEmptyPass() {
        #expect(snapshot(windowCount: 0, applicationCount: 0).summaryLine
            == "listed 0 windows from 0 applications in 71.2 ms")
    }

    @Test func summaryStopsAfterTheCountsWhenNothingWentWrong() {
        #expect(!snapshot().summaryLine.contains(";"))
    }

    /// An application missing from the panel is explained by name and reason,
    /// which is how the quickstart tells a wedged application from a bug.
    @Test func summaryNamesEverySkippedApplicationAndWhy() {
        let line = snapshot(skipped: [
            WindowListSnapshot.SkippedApplication(name: "TextEdit", reason: .timedOut),
            WindowListSnapshot.SkippedApplication(name: "Foo", reason: .permissionMissing),
            WindowListSnapshot.SkippedApplication(name: "Bar", reason: .unavailable(.invalidUIElement)),
            WindowListSnapshot.SkippedApplication(name: "Baz", reason: .malformedAnswer),
        ]).summaryLine
        #expect(line.hasSuffix(
            "; skipped TextEdit (timed out), Foo (permission missing), "
                + "Bar (error -25202), Baz (malformed answer)"
        ))
    }

    @Test func summaryCountsElementsLostForWantOfAWindowID() {
        #expect(snapshot(droppedWithoutID: 1).summaryLine
            .hasSuffix("; dropped 1 elements without a window id"))
    }

    @Test func skippedApplicationsComeBeforeDroppedElements() {
        let line = snapshot(
            skipped: [WindowListSnapshot.SkippedApplication(name: "TextEdit", reason: .timedOut)],
            droppedWithoutID: 1
        ).summaryLine
        #expect(line == "listed 9 windows from 11 applications in 71.2 ms"
            + "; skipped TextEdit (timed out)"
            + "; dropped 1 elements without a window id")
    }

    /// A title never reaches the log, whatever went wrong.
    @Test func summaryNeverCarriesAWindowTitle() {
        let line = snapshot(
            skipped: [WindowListSnapshot.SkippedApplication(name: "TextEdit", reason: .timedOut)],
            droppedWithoutID: 1
        ).summaryLine
        #expect(!line.contains("Downloads"))
    }
}
