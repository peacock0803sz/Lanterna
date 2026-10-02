import AppKit
@testable import Lanterna
import Testing

/// One row on a Space group, or on none.
@MainActor
private func spaceRow(
  _ windowID: CGWindowID,
  group: Int?,
  title: String = "Window",
  isMinimized: Bool = false,
  isOnOtherSpace: Bool = false
) -> WindowItem {
  WindowItem(
    id: WindowItem.Identifier(windowID: windowID),
    ownerProcessIdentifier: pid_t(windowID),
    appName: "App\(windowID)",
    bundleIdentifier: nil,
    windowTitle: title,
    kind: .standard,
    isMinimized: isMinimized,
    isOnOtherSpace: isOnOtherSpace,
    spaceGroup: group.map { SpaceGroup(order: $0, title: "Desktop \($0 + 1)", detail: $0 == 0 ? "shown" : nil) },
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

/// A running application with no window.
@MainActor
private func applicationRow(_ pid: pid_t) -> WindowItem {
  WindowItem(
    id: .application(pid),
    ownerProcessIdentifier: pid,
    appName: "Music",
    bundleIdentifier: nil,
    windowTitle: "",
    kind: .standard,
    isMinimized: false,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - PanelLayoutSpaceTests

/// The list grouped by Space: groups in the order their Spaces draw, each
/// under a heading, with the parked sections where their placement puts
/// them.
@MainActor
struct PanelLayoutSpaceTests {

  // MARK: Internal

  /// Groups draw in their order, each heading followed by its rows, and
  /// the arrows step through the rows as they are drawn.
  @Test
  func groupsDrawInOrderUnderTheirHeadings() {
    let rows = [spaceRow(1, group: 1), spaceRow(2, group: 0), spaceRow(3, group: 1)]
    let layout = PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: bySpace)
    #expect(headings(layout) == ["Desktop 1", "Desktop 2"])
    #expect(layout.rowIDs == [rows[1].id, rows[0].id, rows[2].id])
    #expect(layout.drawnRowCount == 5)
  }

  /// One group draws no heading, so the list reads as it does ungrouped.
  @Test
  func oneGroupDrawsNoHeading() {
    let rows = [spaceRow(1, group: 0), spaceRow(2, group: 0), spaceRow(3, group: 0, isMinimized: true)]
    var grouping = bySpace
    grouping.placements[.minimized] = .withinGroup
    let grouped = PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: grouping)
    let flat = PanelLayout.make(rows: rows, modes: .defaults, query: "")
    #expect(headings(grouped).isEmpty)
    #expect(grouped.rowIDs == flat.rowIDs)
    #expect(grouped.drawnRowCount == flat.drawnRowCount)
  }

  /// Without any Space known, everything is one group with no heading.
  @Test
  func noKnownSpaceIsOneGroup() {
    let rows = [spaceRow(1, group: nil), spaceRow(2, group: nil)]
    let layout = PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: bySpace)
    #expect(headings(layout).isEmpty)
    #expect(layout.rowIDs == rows.map(\.id))
  }

  /// Rows on another Space join their own group instead of the parked
  /// section, while a hiding mode still hides them.
  @Test
  func otherSpaceRowsJoinTheirGroup() {
    let elsewhere = spaceRow(2, group: 1, isOnOtherSpace: true)
    let rows = [spaceRow(1, group: 0), elsewhere]
    var modes = DisplayModes.defaults
    modes.otherSpace = .separateAtBottom
    let layout = PanelLayout.make(rows: rows, modes: modes, query: "", grouping: bySpace)
    #expect(headings(layout) == ["Desktop 1", "Desktop 2"])
    #expect(subgroups(layout).isEmpty)
    modes.otherSpace = .hide
    let hidden = PanelLayout.make(rows: rows, modes: modes, query: "", grouping: bySpace)
    #expect(!hidden.rowIDs.contains(elsewhere.id))
  }

  /// A minimized window on another Space parks the way minimized windows
  /// park, inside its own group when placed there.
  @Test
  func aParkedRowParksInsideItsGroup() {
    let parked = spaceRow(3, group: 1, isMinimized: true, isOnOtherSpace: true)
    let rows = [spaceRow(1, group: 0), spaceRow(2, group: 1), parked]
    var grouping = bySpace
    grouping.placements[.minimized] = .withinGroup
    let layout = PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: grouping)
    #expect(subgroups(layout) == ["minimized in 1"])
    #expect(layout.rowIDs.last == parked.id)
    grouping.placements[.minimized] = .endOfList
    let atEnd = PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: grouping)
    #expect(subgroups(atEnd) == ["minimized at end"])
  }

  /// Applications with no window sit after every group, shown or parked.
  @Test(arguments: [DisplayMode.show, .separateAtBottom])
  func applicationRowsComeLast(mode: DisplayMode) {
    let music = applicationRow(50)
    let rows = [spaceRow(1, group: 0), music, spaceRow(2, group: 1)]
    var modes = DisplayModes.defaults
    modes.windowlessApp = mode
    var grouping = bySpace
    grouping.placements[.windowlessApp] = .withinGroup
    let layout = PanelLayout.make(rows: rows, modes: modes, query: "", grouping: grouping)
    #expect(layout.rowIDs.last == music.id)
    #expect(subgroups(layout) == ["windowlessApp at end"])
  }

  /// Grouping off ignores where the sections were set to go.
  @Test
  func noGroupingIgnoresPlacements() {
    let rows = [spaceRow(1, group: 0), spaceRow(2, group: 1, isMinimized: true)]
    var grouping = GroupingPolicy()
    grouping.placements[.minimized] = .withinGroup
    let layout = PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: grouping)
    #expect(headings(layout).isEmpty)
    #expect(subgroups(layout) == ["minimized at end"])
  }

  // MARK: Private

  private var bySpace: GroupingPolicy {
    var grouping = GroupingPolicy()
    grouping.mode = .bySpace
    return grouping
  }

  private func headings(_ layout: PanelLayout) -> [String] {
    layout.blocks.compactMap { block in
      if case .groupHeading(let heading, _) = block {
        heading.title
      } else {
        nil
      }
    }
  }

  private func subgroups(_ layout: PanelLayout) -> [String] {
    layout.blocks.compactMap { block in
      guard case .subgroupHeading(let subgroup, let group) = block else { return nil }
      return group.map { "\(subgroup) in \($0)" } ?? "\(subgroup) at end"
    }
  }

}
