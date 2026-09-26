import AppKit
@testable import Lanterna
import Testing

/// The summary line is what the manual acceptance check greps, so its wording
/// is pinned down here.
@MainActor
struct WindowListSnapshotTests {
    private func item(_ windowID: CGWindowID, isOnOtherSpace: Bool = false) -> WindowItem {
        WindowItem(
            id: WindowItem.Identifier(windowID: windowID),
            ownerProcessIdentifier: 0,
            appName: "Finder",
            bundleIdentifier: nil,
            windowTitle: "Downloads",
            kind: .standard,
            isMinimized: false,
            isOnOtherSpace: isOnOtherSpace,
            icon: NSImage()
        )
    }

    /// The first `onOtherSpace` of the windows are on another Space.
    private func snapshot(
        windowCount: Int = 9,
        onOtherSpace: Int = 0,
        applicationCount: Int = 11,
        duration: Duration = .milliseconds(71.2),
        skipped: [WindowListSnapshot.SkippedApplication] = [],
        droppedWithoutID: Int = 0
    ) -> WindowListSnapshot {
        WindowListSnapshot(
            items: (0 ..< windowCount).map { item(CGWindowID($0), isOnOtherSpace: $0 < onOtherSpace) },
            applicationCount: applicationCount,
            gatheringDuration: duration,
            skipped: skipped,
            droppedWithoutID: droppedWithoutID,
            gatheredAt: .now
        )
    }

    @Test func idsAreUniqueAcrossTheList() {
        #expect(Set(snapshot().items.map(\.id)).count == 9)
    }

    @Test func summaryReportsCountsAndDuration() {
        #expect(snapshot().summaryLine == "listed 9 windows from 11 applications in 71.2 ms")
    }

    /// An empty pass is reported in the same words, so the manual acceptance
    /// check's grep finds the line whether or not anything was listed.
    @Test func summaryReportsAnEmptyPass() {
        #expect(snapshot(windowCount: 0, applicationCount: 0).summaryLine
            == "listed 0 windows from 0 applications in 71.2 ms")
    }

    @Test func summaryStopsAfterTheCountsWhenNothingWentWrong() {
        #expect(!snapshot().summaryLine.contains(";"))
    }

    /// An application missing from the panel is explained by name and reason,
    /// which is how the manual acceptance check tells a wedged application
    /// from a bug.
    @Test func summaryNamesEverySkippedApplicationAndWhy() {
        let line = snapshot(skipped: [
            WindowListSnapshot.SkippedApplication(name: "TextEdit", reason: .timedOut, processIdentifier: 101),
            WindowListSnapshot.SkippedApplication(name: "Foo", reason: .permissionMissing, processIdentifier: 102),
            WindowListSnapshot.SkippedApplication(
                name: "Bar", reason: .unavailable(.invalidUIElement), processIdentifier: 103
            ),
            WindowListSnapshot.SkippedApplication(name: "Baz", reason: .malformedAnswer, processIdentifier: 104),
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
            skipped: [
                WindowListSnapshot.SkippedApplication(
                    name: "TextEdit",
                    reason: .timedOut,
                    processIdentifier: 101
                ),
            ],
            droppedWithoutID: 1
        ).summaryLine
        #expect(line == "listed 9 windows from 11 applications in 71.2 ms"
            + "; skipped TextEdit (timed out)"
            + "; dropped 1 elements without a window id")
    }

    /// Rows on another Space are counted straight after the totals, ahead of
    /// anything that went wrong.
    @Test func rowsOnOtherSpacesComeBeforeSkippedApplications() {
        let line = snapshot(
            onOtherSpace: 2,
            skipped: [
                WindowListSnapshot.SkippedApplication(
                    name: "TextEdit",
                    reason: .timedOut,
                    processIdentifier: 101
                ),
            ]
        ).summaryLine
        #expect(line == "listed 9 windows from 11 applications in 71.2 ms"
            + "; 2 on other Spaces"
            + "; skipped TextEdit (timed out)")
    }

    /// A title never reaches the log, whatever went wrong.
    @Test func summaryNeverCarriesAWindowTitle() {
        let line = snapshot(
            skipped: [
                WindowListSnapshot.SkippedApplication(
                    name: "TextEdit",
                    reason: .timedOut,
                    processIdentifier: 101
                ),
            ],
            droppedWithoutID: 1
        ).summaryLine
        #expect(!line.contains("Downloads"))
    }
}
