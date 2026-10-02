import AppKit
@testable import Lanterna
import Testing

/// One row of an application known by its bundle identifier.
@MainActor
private func appRow(
  _ windowID: CGWindowID,
  app: String,
  bundle: String?,
  title: String = "Window",
  isMinimized: Bool = false,
  isHidden: Bool = false
) -> WindowItem {
  WindowItem(
    id: WindowItem.Identifier(windowID: windowID),
    ownerProcessIdentifier: pid_t(windowID),
    appName: app,
    bundleIdentifier: bundle,
    windowTitle: title,
    kind: .standard,
    isMinimized: isMinimized,
    isHidden: isHidden,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - PanelLayoutManualTests

/// The list grouped the way the user assigned applications.
@MainActor
struct PanelLayoutManualTests {

  // MARK: Internal

  /// The documented example: two named groups, hidden apps inside each
  /// group, minimized windows at the end, and no heading for the empty
  /// third group.
  @Test
  func theDocumentedExampleLaysOutAsWritten() {
    let ghostty = appRow(1, app: "Ghostty", bundle: "com.mitchellh.ghostty")
    let xcode = appRow(2, app: "Xcode", bundle: "com.apple.dt.Xcode")
    let safari = appRow(3, app: "Safari", bundle: "com.apple.Safari")
    let notes = appRow(4, app: "Notes", bundle: "com.apple.Notes", isHidden: true)
    let slack = appRow(5, app: "Slack", bundle: "com.tinyspeck.slackmacgap")
    let mail = WindowItem(
      id: .application(6),
      ownerProcessIdentifier: 6,
      appName: "Mail",
      bundleIdentifier: "com.apple.mail",
      windowTitle: "",
      kind: .standard,
      isMinimized: false,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
    let preview = appRow(7, app: "Preview", bundle: "com.apple.Preview", isMinimized: true)
    var modes = DisplayModes.defaults
    modes.windowlessApp = .show
    var policy = manual(count: 3, style: .name)
    policy.names = [1: "Work", 2: "Chat"]
    policy.assignments = [
      GroupAssignment(bundleID: "com.apple.dt.Xcode", group: 1),
      GroupAssignment(bundleID: "com.apple.Safari", group: 1),
      GroupAssignment(bundleID: "com.apple.Notes", group: 1),
      GroupAssignment(bundleID: "com.tinyspeck.slackmacgap", group: 2),
      GroupAssignment(bundleID: "com.apple.mail", group: 2),
    ]
    policy.placements[.hiddenApp] = .withinGroup
    let rows = [ghostty, xcode, safari, notes, slack, mail, preview]
    let layout = PanelLayout.make(rows: rows, modes: modes, query: "", grouping: policy)
    #expect(lines(layout) == [
      "[1] Work",
      "Ghostty",
      "Xcode",
      "Safari",
      "  hiddenApp",
      "Notes",
      "[2] Chat",
      "Slack",
      "Mail",
      "minimized",
      "Preview",
    ])
  }

  /// Unassigned applications, applications without a bundle identifier,
  /// and assignments past the count all join the first group; matching
  /// ignores case and the first assignment wins.
  @Test
  func unplacedRowsJoinTheFirstGroup() {
    var policy = manual(count: 2, style: .number)
    policy.assignments = [
      GroupAssignment(bundleID: "COM.example.Two", group: 2),
      GroupAssignment(bundleID: "com.example.two", group: 1),
      GroupAssignment(bundleID: "com.example.far", group: 7),
    ]
    #expect(policy.group(forBundleID: "com.example.two") == 2)
    #expect(policy.group(forBundleID: "com.example.far") == 1)
    #expect(policy.group(forBundleID: "com.example.none") == 1)
    #expect(policy.group(forBundleID: nil) == 1)
  }

  /// The three heading styles: the number alone, the name or the number
  /// when the name is blank, and the group's application names in order
  /// without repeats.
  @Test
  func headingsFollowTheStyle() {
    let rows = [
      appRow(1, app: "Safari", bundle: "a"),
      appRow(2, app: "Safari", bundle: "a"),
      appRow(3, app: "Mail", bundle: "b"),
      appRow(4, app: "Slack", bundle: "c"),
    ]
    var policy = manual(count: 2, style: .number)
    policy.names = [1: "  ", 2: "Chat"]
    policy.assignments = [GroupAssignment(bundleID: "c", group: 2)]
    #expect(titles(PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: policy)) == ["Group 1", "Group 2"])
    policy.headingStyle = .name
    #expect(titles(PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: policy)) == ["Group 1", "Chat"])
    policy.headingStyle = .appNames
    #expect(titles(PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: policy)) == ["Safari, Mail", "Slack"])
  }

  /// An application whose rows all sit in a section gathered after every
  /// group is not named in its group's heading: the heading names only
  /// the applications drawn under it.
  @Test
  func appNamesLeaveOutRowsGatheredAtTheEnd() {
    let rows = [
      appRow(1, app: "Safari", bundle: "a"),
      appRow(2, app: "Preview", bundle: "b", isMinimized: true),
      appRow(3, app: "Slack", bundle: "c"),
    ]
    var policy = manual(count: 2, style: .appNames)
    policy.assignments = [GroupAssignment(bundleID: "c", group: 2)]
    let layout = PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: policy)
    #expect(lines(layout) == ["[1] Safari", "Safari", "[2] Slack", "Slack", "minimized", "Preview"])
  }

  /// One group with rows, or grouping off, reads exactly as the list does
  /// ungrouped, whatever the placements say.
  @Test
  func aSingleFilledGroupReadsAsTheFlatList() {
    let rows = [appRow(1, app: "Safari", bundle: "a"), appRow(2, app: "Mail", bundle: "b", isMinimized: true)]
    var policy = manual(count: 3, style: .name)
    policy.placements[.minimized] = .withinGroup
    let grouped = PanelLayout.make(rows: rows, modes: .defaults, query: "", grouping: policy)
    let flat = PanelLayout.make(rows: rows, modes: .defaults, query: "")
    #expect(lines(grouped) == lines(flat))
  }

  // MARK: Private

  private func manual(count: Int, style: GroupHeadingStyle) -> GroupingPolicy {
    var policy = GroupingPolicy()
    policy.mode = .manual
    policy.groupCount = count
    policy.headingStyle = style
    return policy
  }

  private func titles(_ layout: PanelLayout) -> [String] {
    layout.blocks.compactMap { block in
      if case .groupHeading(let heading, _) = block {
        heading.title
      } else {
        nil
      }
    }
  }

  /// The layout as text: headings with their number, nested subgroups
  /// indented, rows by application name.
  private func lines(_ layout: PanelLayout) -> [String] {
    layout.blocks.map { block in
      switch block {
      case .groupHeading(let heading, _):
        heading.number.map { "[\($0)] \(heading.title)" } ?? heading.title
      case .subgroupHeading(let subgroup, let group):
        group == nil ? "\(subgroup)" : "  \(subgroup)"
      case .row(let window, _):
        window.appName
      }
    }
  }

}
