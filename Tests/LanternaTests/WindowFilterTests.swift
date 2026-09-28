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

    /// Every occurrence is reported, ignoring case.
    @Test func matchedRangesReportEveryOccurrence() {
        let ranges = WindowFilter.matchedRanges(query: "a", in: "Banana")
        #expect(ranges.map { String("Banana"[$0]) } == ["a", "a", "a"])
        let cased = WindowFilter.matchedRanges(query: "SAF", in: "Safari")
        #expect(cased.map { String("Safari"[$0]) } == ["Saf"])
    }

    /// An empty query, or one with no match, reports no ranges. Ranges
    /// never overlap.
    @Test func matchedRangesStayEmptyAndDisjoint() {
        #expect(WindowFilter.matchedRanges(query: "", in: "Safari").isEmpty)
        #expect(WindowFilter.matchedRanges(query: "zzz", in: "Safari").isEmpty)
        let ranges = WindowFilter.matchedRanges(query: "aa", in: "aaa")
        #expect(ranges.count == 1)
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

    /// Opens the engine the way the app does at launch, without a kanji
    /// dictionary. Fails the test when the tables cannot be found.
    private func openEngineWithoutDictionary() -> MigemoEngine {
        let engine = MigemoEngine()
        guard let tables = MigemoEngine.tableDirectoryURL() else {
            Issue.record("kana tables not found")
            return engine
        }
        #expect(engine.open(dictionaryPath: nil, tableDirectory: tables.path))
        return engine
    }

    /// Romaji matches hiragana and katakana rows, and nothing else.
    @Test func kanaRomajiMatchesKanaRowsOnly() {
        let engine = openEngineWithoutDictionary()
        let rows = [
            filterRow(appName: "Memo", windowTitle: "しりょう", windowID: 11),
            filterRow(appName: "Memo", windowTitle: "シリョウ", windowID: 12),
            filterRow(appName: "Safari", windowTitle: "Quarterly planning", windowID: 13),
        ]
        let matched = WindowFilter.matching("shiryou", against: rows, engine: engine)
        #expect(matched.map(\.id.windowID) == [11, 12])
    }

    /// Romaji matching ignores case, like the conventional matching.
    @Test func kanaRomajiIgnoresCase() {
        let engine = openEngineWithoutDictionary()
        let rows = [filterRow(appName: "Memo", windowTitle: "しりょう", windowID: 11)]
        #expect(WindowFilter.matching("SHIRYOU", against: rows, engine: engine).count == 1)
    }

    /// Conventional English queries keep matching through the engine path.
    @Test func conventionalEnglishStillMatchesThroughEngine() {
        let engine = openEngineWithoutDictionary()
        let rows = [filterRow(appName: "Safari", windowTitle: "Quarterly planning", windowID: 1)]
        #expect(WindowFilter.matching("safari", against: rows, engine: engine).count == 1)
        #expect(WindowFilter.matching("SAFARI", against: rows, engine: engine).count == 1)
    }

    /// An empty query returns everything without judging a row.
    @Test func emptyQueryReturnsEverythingThroughEngine() {
        let engine = openEngineWithoutDictionary()
        let rows = [filterRow(appName: "Memo", windowTitle: "しりょう", windowID: 11)]
        #expect(WindowFilter.matching("", against: rows, engine: engine).map(\.id) == rows.map(\.id))
    }

    /// A query matching nothing yields no rows, and clearing recovers all.
    @Test func zeroMatchThenClearRecovers() {
        let engine = openEngineWithoutDictionary()
        let rows = [filterRow(appName: "Memo", windowTitle: "しりょう", windowID: 11)]
        #expect(WindowFilter.matching("zzzqx", against: rows, engine: engine).isEmpty)
        #expect(WindowFilter.matching("", against: rows, engine: engine).count == 1)
    }

    /// A query no pattern can parse matches literally instead of failing.
    @Test func invalidPatternFallsBackToLiteral() {
        let engine = openEngineWithoutDictionary()
        let rows = [filterRow(appName: "T", windowTitle: "data[0]", windowID: 21)]
        #expect(WindowFilter.matching("[", against: rows, engine: engine).count == 1)
        #expect(MigemoEngine.escapedLiteral("[a]") == "\\[a\\]")
    }

    /// Matched ranges cover the whole matched span, not the query length.
    @Test func matchedRangesCoverWholeSpans() {
        let engine = openEngineWithoutDictionary()
        let kanaRanges = WindowFilter.matchedRanges(query: "shiryou", in: "しりょう", engine: engine)
        #expect(kanaRanges.count == 1)
        #expect(kanaRanges.first.map { "しりょう"[$0] } == "しりょう")
        let latinRanges = WindowFilter.matchedRanges(query: "safari", in: "Safari", engine: engine)
        #expect(latinRanges.count == 1)
        #expect(latinRanges.first.map { "Safari"[$0] } == "Safari")
    }

    /// Opens the engine with a small dictionary written to a temporary file.
    private func openEngineWithDictionary(_ entries: String) throws -> MigemoEngine {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("migemo-dict")
        try entries.write(to: url, atomically: true, encoding: .utf8)
        let engine = MigemoEngine()
        let tables = try #require(MigemoEngine.tableDirectoryURL())
        #expect(engine.open(dictionaryPath: url.path, tableDirectory: tables.path))
        return engine
    }

    /// A kanji reading matches its kanji row when a dictionary is open.
    @Test func kanjiReadingMatchesWithDictionary() throws {
        let engine = try openEngineWithDictionary("ぎじろく\t議事録\n")
        #expect(engine.dictionaryActive)
        let rows = [
            filterRow(appName: "Notes", windowTitle: "議事録", windowID: 31),
            filterRow(appName: "Memo", windowTitle: "しりょう", windowID: 32),
            filterRow(appName: "Safari", windowTitle: "Quarterly planning", windowID: 33),
        ]
        let matched = WindowFilter.matching("gijiroku", against: rows, engine: engine)
        #expect(matched.map(\.id.windowID) == [31])
    }

    /// Without a dictionary the same reading matches nothing.
    @Test func kanjiDoesNotMatchWithoutDictionary() {
        let engine = openEngineWithoutDictionary()
        let rows = [filterRow(appName: "Notes", windowTitle: "議事録", windowID: 31)]
        #expect(WindowFilter.matching("gijiroku", against: rows, engine: engine).isEmpty)
    }

    /// Kanji highlight ranges cover the whole kanji span.
    @Test func kanjiRangesCoverKanjiSpan() throws {
        let engine = try openEngineWithDictionary("ぎじろく\t議事録\n")
        let ranges = WindowFilter.matchedRanges(query: "gijiroku", in: "議事録", engine: engine)
        #expect(ranges.count == 1)
        #expect(ranges.first.map { "議事録"[$0] } == "議事録")
    }

    /// A broken dictionary falls back to kana-only matching.
    @Test func invalidDictionaryFallsBack() throws {
        let engine = try openEngineWithDictionary("this line has no tab\n")
        #expect(!engine.dictionaryActive)
        let kana = [filterRow(appName: "Memo", windowTitle: "しりょう", windowID: 32)]
        #expect(WindowFilter.matching("shiryou", against: kana, engine: engine).count == 1)
        let kanji = [filterRow(appName: "Notes", windowTitle: "議事録", windowID: 31)]
        #expect(WindowFilter.matching("gijiroku", against: kanji, engine: engine).isEmpty)
    }

    /// A subsequence query matches when its characters appear in order.
    @Test func subsequenceQueryMatchesInOrder() {
        #expect(WindowFilter.matching("sfr", against: rows, fuzzy: true).map(\.id) == [rows[0].id])
    }

    /// A query whose characters never appear in order matches nothing.
    @Test func outOfOrderQueryMatchesNothing() {
        #expect(WindowFilter.matching("sdf", against: rows, fuzzy: true).isEmpty)
    }

    /// Fuzzy matching never narrows substring matching.
    @Test func fuzzyMatchingKeepsSubstringMatches() {
        for query in ["safari", "SAF", "download", "a"] {
            let plain = WindowFilter.matching(query, against: rows).map(\.id)
            let fuzzy = WindowFilter.matching(query, against: rows, fuzzy: true).map(\.id)
            #expect(fuzzy.count >= plain.count)
            #expect(plain.allSatisfy { fuzzy.contains($0) })
        }
    }

    /// Fuzzy matching ignores case.
    @Test func fuzzyMatchingIgnoresCase() {
        #expect(WindowFilter.matching("SFR", against: rows, fuzzy: true).map(\.id) == [rows[0].id])
    }

    /// An empty fuzzy query returns the input unchanged.
    @Test func emptyFuzzyQueryReturnsTheInputUnchanged() {
        #expect(WindowFilter.matching("", against: rows, fuzzy: true).map(\.id) == rows.map(\.id))
    }

    /// Subsequence ranges mark each query character where it matched.
    @Test func subsequenceRangesMarkEachCharacter() {
        let ranges = WindowFilter.subsequenceRanges(query: "sfr", in: "Safari")
        #expect(ranges.map { String("Safari"[$0]) } == ["S", "f", "r"])
    }

    /// Subsequence ranges are empty when the query never appears in order.
    @Test func subsequenceRangesAreEmptyWithoutAMatch() {
        #expect(WindowFilter.subsequenceRanges(query: "sdf", in: "Safari").isEmpty)
    }
}
