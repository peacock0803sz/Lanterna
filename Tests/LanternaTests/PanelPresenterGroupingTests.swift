import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// One row of an application known by its bundle identifier, on a Space
/// group when one is given.
@MainActor
private func groupedRow(
  _ windowID: CGWindowID,
  bundle: String,
  title: String = "Window",
  space: Int? = nil
) -> WindowItem {
  WindowItem(
    id: WindowItem.Identifier(windowID: windowID),
    ownerProcessIdentifier: pid_t(windowID),
    appName: "App\(windowID)",
    bundleIdentifier: bundle,
    windowTitle: title,
    kind: .standard,
    isMinimized: false,
    spaceGroup: space.map { SpaceGroup(order: $0, title: "Desktop \($0 + 1)", detail: nil) },
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

private func press(_ keyCode: Int, characters: String = "") -> PanelKeystroke {
  PanelKeystroke(keyCode: UInt16(keyCode), modifiers: [], isARepeat: false, characters: characters)
}

// MARK: - PanelPresenterGroupingTests

/// A grouped list opened from the presenter: the choice opens on the row
/// recent use put second, wherever its group draws, and letting go of
/// Command takes that row.
@MainActor
struct PanelPresenterGroupingTests {

  // MARK: Internal

  /// The window in front belongs to the second manual group, so the first
  /// group draws ahead of it. The panel still opens on the previous
  /// window, and a quick release switches there.
  @Test
  func aManualGroupDrawnAheadOfTheFrontWindowOpensOnThePreviousOne() {
    let rows = [
      groupedRow(1, bundle: "com.example.front"),
      groupedRow(2, bundle: "com.example.previous"),
      groupedRow(3, bundle: "com.example.front"),
      groupedRow(4, bundle: "com.example.previous"),
    ]
    var policy = GroupingPolicy()
    policy.mode = .manual
    policy.groupCount = 2
    policy.assignments = [GroupAssignment(bundleID: "com.example.front", group: 2)]
    expectOpensAndTakes(rows[1], drawn: [rows[1], rows[3], rows[0], rows[2]], rows: rows, policy: policy)
  }

  /// The window in front is on a later display's Space, so the shown
  /// Space draws ahead of it. The panel still opens on the previous
  /// window, and a quick release switches there.
  @Test
  func aSpaceGroupDrawnAheadOfTheFrontWindowOpensOnThePreviousOne() {
    let rows = [
      groupedRow(1, bundle: "com.example.a", space: 1),
      groupedRow(2, bundle: "com.example.b", space: 0),
      groupedRow(3, bundle: "com.example.c", space: 1),
      groupedRow(4, bundle: "com.example.d", space: 0),
    ]
    var policy = GroupingPolicy()
    policy.mode = .bySpace
    expectOpensAndTakes(rows[1], drawn: [rows[1], rows[3], rows[0], rows[2]], rows: rows, policy: policy)
  }

  /// A query that hides the chosen row falls back to its best match, not
  /// to whichever match the first group draws on top.
  @Test
  func aQueryHidingTheChoiceFallsBackToTheBestMatch() {
    let rows = [
      groupedRow(1, bundle: "com.example.front", title: "alpha one"),
      groupedRow(2, bundle: "com.example.previous", title: "beta"),
      groupedRow(3, bundle: "com.example.front", title: "alpha two"),
      groupedRow(4, bundle: "com.example.previous", title: "alpha three"),
    ]
    var policy = GroupingPolicy()
    policy.mode = .manual
    policy.groupCount = 2
    policy.assignments = [GroupAssignment(bundleID: "com.example.front", group: 2)]
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    fixture.presenter.grouping = policy
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    #expect(fixture.presenter.selection.chosenID == rows[1].id)
    for character in "alpha" {
      _ = fixture.presenter.handleKeyStroke(press(kVK_ANSI_A, characters: String(character)))
    }
    #expect(fixture.surface.updatedLists.last?.map(\.id) == [rows[3].id, rows[0].id, rows[2].id])
    #expect(fixture.presenter.selection.chosenID == rows[0].id)
  }

  // MARK: Private

  private func expectOpensAndTakes(
    _ expected: WindowItem,
    drawn: [WindowItem],
    rows: [WindowItem],
    policy: GroupingPolicy,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows, closesOnCommandRelease: true)
    fixture.presenter.grouping = policy
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    #expect(fixture.surface.presentedLists.first?.map(\.id) == drawn.map(\.id), sourceLocation: sourceLocation)
    #expect(fixture.presenter.selection.chosenID == expected.id, sourceLocation: sourceLocation)
    #expect(
      fixture.log.lines.contains(where: { $0.contains("mru first (\(rows[0].id.logWord))") }),
      sourceLocation: sourceLocation
    )
    fixture.presenter.handleCommandRelease()
    #expect(fixture.switcher.targets.map(\.id) == [expected.id], sourceLocation: sourceLocation)
  }

}
