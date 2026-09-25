import AppKit
@testable import Lanterna
import Testing

/// Rows with distinct names, because what the filter reads is the names.
///
/// The combined string the filter matches against is app name, one space,
/// then window title, so the rows below pin that shape through cases that
/// would pass either way if it only ever saw one of the two.
@MainActor
private func filterRow(appName: String, windowTitle: String, windowID: CGWindowID) -> WindowItem {
    WindowItem(
        id: WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: 0,
        appName: appName,
        bundleIdentifier: nil,
        windowTitle: windowTitle,
        kind: .standard,
        isMinimized: false,
        icon: NSImage(size: NSSize(width: 1, height: 1))
    )
}

/// The matching contract, held without any window server.
///
/// Every case here runs against rows made by hand (contracts/filtering.md):
/// which rows match is decided by the test, never by watching real windows.
@MainActor
struct WindowFilterTests {
    private var rows: [WindowItem] {
        [
            filterRow(appName: "Safari", windowTitle: "Quarterly planning", windowID: 1),
            filterRow(appName: "Finder", windowTitle: "Downloads", windowID: 2),
            filterRow(appName: "Terminal", windowTitle: "swift build", windowID: 3),
        ]
    }

    /// An empty query returns the input unchanged, without judging a row.
    @Test func emptyQueryReturnsTheInputUnchanged() {
        #expect(WindowFilter.matching("", against: rows).map(\.id) == rows.map(\.id))
    }

    /// Filtering keeps the order it found; it never sorts.
    @Test func matchingKeepsTheInputOrder() {
        let matched = WindowFilter.matching("a", against: rows)
        #expect(matched.map(\.id) == rows.map(\.id))
    }

    /// Matching ignores case.
    @Test func matchingIgnoresCase() {
        #expect(WindowFilter.matching("safari", against: rows).map(\.id) == [rows[0].id])
        #expect(WindowFilter.matching("SAF", against: rows).map(\.id) == [rows[0].id])
    }

    /// Both the app name and the window title are matched.
    @Test func matchingReadsBothAppNameAndTitle() {
        #expect(WindowFilter.matching("finder", against: rows).map(\.id) == [rows[1].id])
        #expect(WindowFilter.matching("download", against: rows).map(\.id) == [rows[1].id])
    }

    /// A query with no match yields an empty list, not an error.
    @Test func queryWithNoMatchYieldsAnEmptyList() {
        #expect(WindowFilter.matching("zzz", against: rows).isEmpty)
    }

    /// One ASCII letter or digit is accepted; nothing else single is.
    @Test func singleASCIIAlphanumericsAreAccepted() {
        #expect(WindowFilter.allowedText("a") == "a")
        #expect(WindowFilter.allowedText("Z") == "Z")
        #expect(WindowFilter.allowedText("7") == "7")
    }

    /// A directly typed space, symbol, or control character is refused.
    @Test func singleASCIISymbolsAreRefused() {
        #expect(WindowFilter.allowedText(" ") == nil)
        #expect(WindowFilter.allowedText("-") == nil)
        #expect(WindowFilter.allowedText("/") == nil)
        #expect(WindowFilter.allowedText("") == nil)
    }

    /// Anything longer than one character, or holding non-ASCII, is taken
    /// verbatim as a confirmed string; origin is not distinguished.
    @Test func longerOrNonASCIIStringsAreTakenVerbatim() {
        #expect(WindowFilter.allowedText("あ") == "あ")
        #expect(WindowFilter.allowedText("日本語") == "日本語")
        #expect(WindowFilter.allowedText("a b") == "a b")
    }
}
