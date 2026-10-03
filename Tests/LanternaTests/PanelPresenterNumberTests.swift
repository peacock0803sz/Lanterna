import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

// MARK: - PanelPresenterNumberTests

/// What number presses do to a panel that is up.
///
/// Digits with Command or Option held name rows while the number jump
/// stands enabled; letting go commits the named row through the same
/// release path as ever. What is settled here is that wiring, and only
/// it — which physical keys count as digits is settled in
/// `DigitValueTests`, and the table answering them in
/// `KeyBindingNumberTests`.
@MainActor
struct PanelPresenterNumberTests {

  // MARK: Internal

  @Test
  func digitPreviewMovesTheChoice() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .command, through: fixture)

    #expect(fixture.presenter.selection.chosenID == fixture.windows[2].id)
  }

  @Test
  func optionDigitMovesTheChoiceTheSameWay() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .option, through: fixture)

    #expect(fixture.presenter.selection.chosenID == fixture.windows[2].id)
  }

  @Test
  func digitLeavesTheQueryAlone() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .command, through: fixture)

    #expect(!fixture.surface.updatedQueries.contains("3"))
  }

  @Test
  func invalidNumberKeepsTheChoice() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(9, modifiers: .command, through: fixture)
    pressDigit(9, modifiers: .command, through: fixture)
    let before = fixture.presenter.selection.chosenID

    #expect(fixture.presenter.selection.chosenID == before)
  }

  @Test
  func commandReleaseCommitsTheNamedRow() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .command, through: fixture)
    fixture.presenter.handleCommandRelease()

    #expect(fixture.surface.dismissCount == 1)
    let named = fixture.windows[2]
    #expect(fixture.log.lines.contains(where: {
      $0.hasPrefix("committed ") && $0.contains(named.displayTitle)
    }))
  }

  @Test
  func optionReleaseCommitsTheNamedRow() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .option, through: fixture)
    fixture.presenter.handleOptionRelease()

    #expect(fixture.surface.dismissCount == 1)
    let named = fixture.windows[2]
    #expect(fixture.log.lines.contains(where: {
      $0.hasPrefix("committed ") && $0.contains(named.displayTitle)
    }))
    #expect(fixture.log.lines.contains(
      "committed \(named.appName) — \(named.displayTitle) "
        + "(\(named.id.logWord)) 4.8 ms after Option was released"
    ))
  }

  @Test
  func cancelAfterDigitsCommitsNothing() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    pressDigit(3, modifiers: .command, through: fixture)
    _ = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: UInt16(kVK_Escape),
      modifiers: [],
      isARepeat: false
    ))

    #expect(!fixture.surface.isPresented)
    #expect(!fixture.log.lines.contains(where: { $0.hasPrefix("committed ") }))
  }

  @Test
  func closedPanelIgnoresDigits() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    let disposition = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_3),
      modifiers: .command,
      isARepeat: false,
      characters: "3"
    ))

    #expect(disposition == .passedThrough)
    #expect(fixture.presenter.selection.chosenID == nil)
  }

  @Test
  func heldModifierShowsNumbersInDisplayOrder() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.modifierFlagsChanged([.maskCommand])

    #expect(fixture.surface.numberedRowOrders.last == fixture.windows.map(\.id))
  }

  @Test
  func releasedModifierTakesNumbersDown() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.modifierFlagsChanged([.maskCommand])
    fixture.presenter.modifierFlagsChanged([])

    #expect(fixture.surface.numberedRowOrders.last == [])
  }

  @Test
  func numbersModeShowsNumbersWithoutModifier() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.surface.appearanceHints = .numbers
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

    #expect(fixture.surface.numberedRowOrders.last == fixture.windows.map(\.id))
  }

  @Test
  func numbersModeKeepsNumbersUpAfterRelease() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.surface.appearanceHints = .numbers
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.modifierFlagsChanged([.maskCommand])
    fixture.presenter.modifierFlagsChanged([])

    #expect(fixture.surface.numberedRowOrders.last == fixture.windows.map(\.id))
  }

  @Test
  func switchingTheJumpOffTakesNumbersDown() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    fixture.presenter.numberJump = false

    #expect(fixture.surface.numberedRowOrders.last == [])
  }

  @Test
  func reorderMovesTheRowDownInsideItsGroup() {
    let fixture = groupedFixture()
    pressMove(down: true, through: fixture)

    #expect(fixture.surface.updatedLists.last?.map(\.id) == [
      groupedRows[3].id,
      groupedRows[1].id,
      groupedRows[0].id,
      groupedRows[2].id,
    ])
    #expect(fixture.presenter.selection.chosenID == groupedRows[1].id)
  }

  @Test
  func reorderStopsAtTheGroupEdge() {
    let fixture = groupedFixture()
    pressMove(down: false, through: fixture)

    #expect(fixture.surface.presentedLists.last?.map(\.id) == [
      groupedRows[1].id,
      groupedRows[3].id,
      groupedRows[0].id,
      groupedRows[2].id,
    ])
    #expect(fixture.presenter.selection.chosenID == groupedRows[1].id)
  }

  @Test
  func reorderDoesNotCrossGroups() {
    let fixture = groupedFixture()
    _ = fixture.presenter.handleKeyStroke(pressKeyDown())
    #expect(fixture.presenter.selection.chosenID == groupedRows[3].id)
    pressMove(down: true, through: fixture)

    #expect(fixture.surface.presentedLists.last?.map(\.id) == [
      groupedRows[1].id,
      groupedRows[3].id,
      groupedRows[0].id,
      groupedRows[2].id,
    ])
    #expect(fixture.presenter.selection.chosenID == groupedRows[3].id)
  }

  @Test
  func flatListIgnoresReorder() {
    let fixture = Fixture(entryCount: 4, closesOnCommandRelease: true)
    fixture.presenter.numberReorder = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    let before: [WindowItem.Identifier]? = fixture.surface.updatedLists.last?.map(\.id)
    pressMove(down: true, through: fixture)

    #expect(fixture.surface.updatedLists.last?.map(\.id) == before)
  }

  @Test
  func switchedOffReorderIgnoresMoves() {
    let fixture = groupedFixture(reorder: false)
    pressMove(down: true, through: fixture)

    #expect(fixture.surface.presentedLists.last?.map(\.id) == [
      groupedRows[1].id,
      groupedRows[3].id,
      groupedRows[0].id,
      groupedRows[2].id,
    ])
  }

  @Test
  func narrowedListIgnoresReorder() {
    let fixture = groupedFixture(combination: .filter)
    _ = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_Z),
      modifiers: [],
      isARepeat: false,
      characters: "z"
    ))
    let before: [WindowItem.Identifier]? = fixture.surface.updatedLists.last?.map(\.id)
    let chosen = fixture.presenter.selection.chosenID
    pressMove(down: true, through: fixture)

    #expect(fixture.surface.updatedLists.last?.map(\.id) == before)
    #expect(fixture.presenter.selection.chosenID == chosen)
  }

  @Test
  func reorderReportsTheOrderForSaving() {
    let fixture = groupedFixture()
    var reported = [ManualRowOrder]()
    fixture.presenter.onRowOrderChanged = { reported.append($0) }
    pressMove(down: true, through: fixture)

    #expect(reported.count == 1)
    #expect(reported.first?.keys(forGroup: 1)?.map(\.title) == ["Window 4", "Window 2"])
  }

  // MARK: Private

  private var groupedRows: [WindowItem] {
    [
      groupedRow(1, bundle: "com.example.front"),
      groupedRow(2, bundle: "com.example.previous"),
      groupedRow(3, bundle: "com.example.front"),
      groupedRow(4, bundle: "com.example.previous"),
    ]
  }

  private func groupedFixture(reorder: Bool = true, combination: HotkeyCombination = .forward) -> Fixture {
    let rows = groupedRows
    let fixture = Fixture(store: WindowListStore(fixed: rows), windows: rows)
    var policy = GroupingPolicy()
    policy.mode = .manual
    policy.groupCount = 2
    policy.assignments = [GroupAssignment(bundleID: "com.example.front", group: 2)]
    fixture.presenter.grouping = policy
    fixture.presenter.numberReorder = reorder
    fixture.presenter.handleHotkey(combination, deliveryDelay: nil)
    return fixture
  }

  private func groupedRow(_ windowID: CGWindowID, bundle: String) -> WindowItem {
    WindowItem(
      id: WindowItem.Identifier(windowID: windowID),
      ownerProcessIdentifier: pid_t(windowID),
      appName: "App\(windowID)",
      bundleIdentifier: bundle,
      windowTitle: "Window \(windowID)",
      kind: .standard,
      isMinimized: false,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
  }

  private func pressMove(down: Bool, through fixture: Fixture) {
    _ = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: UInt16(down ? kVK_DownArrow : kVK_UpArrow),
      modifiers: [.command, .shift],
      isARepeat: false
    ))
  }

  private func pressKeyDown() -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(kVK_DownArrow), modifiers: [], isARepeat: false)
  }

  /// The key codes answering as digits on the main row, by value.
  private func keyCode(for digit: Int) -> UInt16 {
    switch digit {
    case 1: UInt16(kVK_ANSI_1)
    case 2: UInt16(kVK_ANSI_2)
    case 3: UInt16(kVK_ANSI_3)
    case 4: UInt16(kVK_ANSI_4)
    case 5: UInt16(kVK_ANSI_5)
    case 6: UInt16(kVK_ANSI_6)
    case 7: UInt16(kVK_ANSI_7)
    case 8: UInt16(kVK_ANSI_8)
    case 9: UInt16(kVK_ANSI_9)
    default: UInt16(kVK_ANSI_0)
    }
  }

  private func pressDigit(
    _ digit: Int,
    modifiers: NSEvent.ModifierFlags,
    through fixture: Fixture
  ) {
    _ = fixture.presenter.handleKeyStroke(PanelKeystroke(
      keyCode: keyCode(for: digit),
      modifiers: modifiers,
      isARepeat: false,
      characters: "\(digit)"
    ))
  }

}
