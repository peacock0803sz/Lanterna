import AppKit
@testable import Lanterna
import Testing

/// Rows with distinct names, so which rows match is decided by the test.
@MainActor
private func layoutRow(
  windowID: CGWindowID,
  title: String,
  isMinimized: Bool = false,
  isHidden: Bool = false,
  isOnOtherSpace: Bool = false
) -> WindowItem {
  WindowItem(
    id: WindowItem.Identifier(windowID: windowID),
    ownerProcessIdentifier: 0,
    appName: "App\(windowID)",
    bundleIdentifier: nil,
    windowTitle: title,
    kind: .standard,
    isMinimized: isMinimized,
    isHidden: isHidden,
    isOnOtherSpace: isOnOtherSpace,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - PanelLayoutTests

/// The list as it draws, held against the split the display modes make:
/// the layout is the one place the three readers of that split now ask.
@MainActor
struct PanelLayoutTests {

  // MARK: Internal

  /// Without a query, every placement the modes make reads back as the
  /// same rows in the same order, with one heading per non-empty subgroup.
  @Test(arguments: [
    DisplayModes.defaults,
    DisplayModes(otherSpace: .separateAtBottom, hiddenApp: .hide, minimized: .show, fullscreen: .show),
    DisplayModes(otherSpace: .hide, hiddenApp: .show, minimized: .hide, fullscreen: .separateAtBottom),
  ])
  func anEmptyQueryKeepsTheDisplayOrder(modes: DisplayModes) {
    let layout = PanelLayout.make(rows: rows, modes: modes, query: "")
    let expected = DisplayModes.displayOrdered(rows, modes: modes, query: "")
    let split = DisplayModes.sections(of: rows, modes: modes, query: "")
    #expect(layout.rowIDs == expected.map(\.id))
    #expect(layout.drawnRowCount == expected.count + split.subgroups.count)
    #expect(layout.drawnRowCount == PanelMetrics.drawnRowCount(rows, modes: modes))
  }

  /// A hidden row the query matches comes back under its heading, the way
  /// the modes alone place it.
  @Test
  func aMatchedHiddenRowComesBackUnderItsHeading() {
    let modes = DisplayModes(otherSpace: .show, hiddenApp: .hide, minimized: .hide, fullscreen: .show)
    let layout = PanelLayout.make(rows: rows, modes: modes, query: "notes")
    #expect(layout.rowIDs == [rows[4].id])
    guard case .subgroupHeading(.minimized, group: nil) = layout.blocks.first else {
      Issue.record("expected the minimized heading first, got \(layout.blocks.map(\.key))")
      return
    }
  }

  /// Ranking by score stays inside each section, as the modes rank it.
  @Test
  func scoreRankingStaysInsideEachSection() {
    let modes = DisplayModes.defaults
    let layout = PanelLayout.make(rows: rows, modes: modes, query: "o", ordering: .score)
    let expected = DisplayModes.displayOrdered(rows, modes: modes, query: "o", ordering: .score)
    #expect(layout.rowIDs == expected.map(\.id))
  }

  /// The remembered row moves to the front of its own section and nowhere
  /// else: a parked row stays parked.
  @Test
  func theRememberedRowLeadsItsOwnSection() {
    let modes = DisplayModes.defaults
    let ordinary = PanelLayout.make(rows: rows, modes: modes, query: "o", memory: rows[2].id)
    #expect(ordinary.rowIDs.first == rows[2].id)
    let parked = PanelLayout.make(rows: rows, modes: modes, query: "o", memory: rows[4].id)
    let parkedIndex = parked.rowIDs.firstIndex(of: rows[4].id)
    let firstParked = parked.rows.firstIndex(where: \.isMinimized)
    #expect(parkedIndex == firstParked)
    #expect(parked.rowIDs.first != rows[4].id)
  }

  /// Naming an owner keeps that owner's rows alone, before matching: a
  /// query never brings another owner's row back.
  @Test
  func anOwnerKeepsOnlyItsRows() {
    let other = WindowItem(
      id: WindowItem.Identifier(windowID: 9),
      ownerProcessIdentifier: 3,
      appName: "Front",
      bundleIdentifier: nil,
      windowTitle: "Front page",
      kind: .standard,
      isMinimized: false,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
    let layout = PanelLayout.make(rows: rows + [other], modes: .defaults, query: "front", owner: 3)
    #expect(layout.rowIDs == [other.id])
    let none = PanelLayout.make(rows: rows, modes: .defaults, query: "", owner: 3)
    #expect(none.rows.isEmpty)
  }

  /// An application with no window stays out by default, comes back
  /// under its heading for a query naming it, mixes in when shown, and
  /// parks last when separated. Being hidden does not move it.
  @Test
  func anApplicationRowFollowsItsOwnMode() {
    let music = WindowItem(
      id: .application(7),
      ownerProcessIdentifier: 7,
      appName: "Music",
      bundleIdentifier: nil,
      windowTitle: "",
      kind: .standard,
      isMinimized: false,
      isHidden: true,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
    let all = rows + [music]
    var modes = DisplayModes.defaults
    #expect(!PanelLayout.make(rows: all, modes: modes, query: "").rowIDs.contains(music.id))
    let searched = PanelLayout.make(rows: all, modes: modes, query: "music")
    #expect(searched.rowIDs == [music.id])
    guard case .subgroupHeading(.windowlessApp, group: nil) = searched.blocks.first else {
      Issue.record("expected the windowless heading, got \(searched.blocks.map(\.key))")
      return
    }
    modes.windowlessApp = .show
    let shown = PanelLayout.make(rows: all, modes: modes, query: "")
    let ordinary = DisplayModes.sections(of: all, modes: modes, query: "").ordinary
    #expect(ordinary.contains { $0.id == music.id })
    #expect(shown.windowCount == shown.rows.count - 1)
    modes.windowlessApp = .separateAtBottom
    #expect(PanelLayout.make(rows: all, modes: modes, query: "").rowIDs.last == music.id)
  }

  /// Window rows are counted and headings are not.
  @Test
  func theWindowCountLeavesHeadingsOut() {
    let layout = PanelLayout.make(rows: rows, modes: .defaults, query: "")
    #expect(layout.windowCount == layout.rows.count)
    #expect(layout.windowCount < layout.drawnRowCount)
  }

  /// Nothing to draw still takes the one line that says so.
  @Test
  func noRowsTakeTheEmptyLine() {
    let layout = PanelLayout.make(rows: [], modes: .defaults, query: "")
    #expect(layout.drawnRowCount == 1)
    #expect(layout.windowCount == 0)
    let unmatched = PanelLayout.make(rows: rows, modes: .defaults, query: "zzz")
    #expect(unmatched.drawnRowCount == 1)
  }

  // MARK: Private

  private let rows = [
    layoutRow(windowID: 1, title: "Front page"),
    layoutRow(windowID: 2, title: "Downloads", isHidden: true),
    layoutRow(windowID: 3, title: "Notebook"),
    layoutRow(windowID: 4, title: "Other desk", isOnOtherSpace: true),
    layoutRow(windowID: 5, title: "Buried notes", isMinimized: true),
  ]

}
