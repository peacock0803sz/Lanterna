import AppKit
import Carbon.HIToolbox
import Testing
@testable import Lanterna

/// Editing the query through the whole presenter: what the control-held
/// keys do to the narrowed list, and what the unbound ones leave alone.
///
/// Drives the presenter rather than the filter, so these say what a
/// press does rather than what one call means. The rules themselves
/// are held in the suites beside this one; here a press goes in and
/// the query on screen is read back out.
@MainActor
struct PanelQueryEditingTests {

  // MARK: Internal

  /// The control-held deletion keys shorten the query the way their
  /// wordless counterparts do, and the panel stays up.
  @Test
  func controlDeletionsShortenTheQuery() {
    let fixture = Fixture(entryCount: 12)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    pressText(fixture, "safarx")
    press(fixture, kVK_ANSI_H, .control, characters: "h")
    #expect(lastQuery(fixture) == "safar")
    #expect(fixture.surface.isPresented)
  }

  /// A word deletion clears letters back to the start, and a
  /// start deletion clears everything, all without closing.
  @Test
  func wordAndStartDeletionsClearBack() {
    let fixture = Fixture(entryCount: 12)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    pressText(fixture, "saf")
    press(fixture, kVK_ANSI_W, .control, characters: "w")
    #expect(lastQuery(fixture) == "")
    #expect(fixture.surface.isPresented)
    pressText(fixture, "term")
    press(fixture, kVK_ANSI_U, .control, characters: "u")
    #expect(lastQuery(fixture) == "")
    #expect(fixture.surface.isPresented)
  }

  /// A confirmed string with a divider inside deletes word by word.
  @Test
  func wordDeletionStopsAtDividers() {
    let fixture = Fixture(entryCount: 12)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    pressText(fixture, "google chrome")
    press(fixture, kVK_ANSI_W, .control, characters: "w")
    #expect(lastQuery(fixture) == "google ")
    press(fixture, kVK_ANSI_W, .control, characters: "w")
    #expect(lastQuery(fixture) == "")
  }

  /// Deleting on an empty query does nothing, and the panel stays up.
  @Test
  func deletingOnAnEmptyQueryDoesNothing() {
    let fixture = Fixture(entryCount: 12)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    let updates = fixture.surface.updatedLists.count
    for code in [kVK_ANSI_H, kVK_ANSI_W, kVK_ANSI_U] {
      press(fixture, code, .control, characters: "x")
    }
    #expect(fixture.surface.updatedLists.count == updates)
    #expect(fixture.surface.isPresented)
  }

  /// Holding a deletion key down keeps deleting, the way Backspace does.
  @Test
  func holdingADeletionRepeatsIt() {
    let fixture = Fixture(entryCount: 12)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    pressText(fixture, "safarx")
    press(fixture, kVK_ANSI_H, .control, characters: "h", repeating: true)
    press(fixture, kVK_ANSI_H, .control, characters: "h", repeating: true)
    #expect(lastQuery(fixture) == "safa")
  }

  /// Control-held letters with no binding go nowhere: the query, the
  /// list, and the choice all stay as they were.
  @Test
  func unboundControlLettersLeaveEverythingAlone() {
    let fixture = Fixture(entryCount: 12)
    fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
    pressText(fixture, "sa")
    let lists = fixture.surface.updatedLists.count
    let choice = fixture.surface.updatedSelections.last
    for code in [kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_O] {
      press(fixture, code, .control, characters: "t")
    }
    #expect(lastQuery(fixture) == "sa")
    #expect(fixture.surface.updatedLists.count == lists)
    #expect(fixture.surface.updatedSelections.last == choice)
  }

  /// Every letter of the row, held with Control while filtering, either
  /// works its binding or is dropped: none of them types.
  @Test
  func everyControlLetterEitherWorksOrIsDropped() {
    let table = KeyBindingTable.defaults
    let letters: [(Int, String, PanelKeyAction)] = [
      (kVK_ANSI_A, "a", .editQuery(.moveToStart)),
      (kVK_ANSI_B, "b", .editQuery(.moveLeft)),
      (kVK_ANSI_D, "d", .editQuery(.deleteForward)),
      (kVK_ANSI_E, "e", .editQuery(.moveToEnd)),
      (kVK_ANSI_F, "f", .editQuery(.moveRight)),
      (kVK_ANSI_G, "g", .cancel(.custom(UInt16(kVK_ANSI_G)))),
      (kVK_ANSI_H, "h", .editQuery(.deleteBackward)),
      (kVK_ANSI_K, "k", .editQuery(.deleteToEnd)),
      (kVK_ANSI_M, "m", .commit(.custom(UInt16(kVK_ANSI_M)))),
      (kVK_ANSI_N, "n", .selectNext),
      (kVK_ANSI_P, "p", .selectPrevious),
      (kVK_ANSI_U, "u", .editQuery(.deleteToStart)),
      (kVK_ANSI_W, "w", .editQuery(.deleteWordBackward)),
    ]
    for (code, characters, meaning) in letters {
      let stroke = PanelKeystroke(
        keyCode: UInt16(code),
        modifiers: .control,
        isARepeat: false,
        characters: characters
      )
      #expect(PanelKeyInput.action(for: stroke, table: table) == meaning)
    }
    for code in
      [
        kVK_ANSI_C,
        kVK_ANSI_I,
        kVK_ANSI_J,
        kVK_ANSI_L,
        kVK_ANSI_O,
        kVK_ANSI_Q,
        kVK_ANSI_R,
        kVK_ANSI_S,
        kVK_ANSI_T,
        kVK_ANSI_V,
        kVK_ANSI_X,
        kVK_ANSI_Y,
        kVK_ANSI_Z,
      ]
    {
      let stroke = PanelKeystroke(
        keyCode: UInt16(code),
        modifiers: .control,
        isARepeat: false,
        characters: "x"
      )
      #expect(PanelKeyInput.action(for: stroke, table: table) == .absorb)
    }
  }

  /// Away from filtering, an unbound Control letter keeps its old fate:
  /// it types or does nothing, exactly as before.
  @Test
  func unboundControlLettersKeepTheirOldFateAwayFromFiltering() {
    let table = KeyBindingTable.defaults
    let stroke = PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_T),
      modifiers: .control,
      isARepeat: false,
      characters: "t"
    )
    #expect(
      PanelKeyInput.action(
        for: stroke,
        table: table,
        numberJumpEnabled: false,
        reorderEnabled: false,
        filtering: false
      ) == .filterText("t")
    )
  }

  // MARK: Private

  private func press(
    _ fixture: Fixture,
    _ keyCode: Int,
    _ modifiers: NSEvent.ModifierFlags,
    characters: String,
    repeating: Bool = false
  ) {
    let stroke = PanelKeystroke(
      keyCode: UInt16(keyCode),
      modifiers: modifiers,
      isARepeat: repeating,
      characters: characters
    )
    #expect(fixture.presenter.handleKeyStroke(stroke) == .absorbed)
  }

  private func pressText(_ fixture: Fixture, _ text: String) {
    // One confirmed string, the way the panel receives pasted words:
    // single letters type and longer runs land verbatim, spaces included.
    press(fixture, Int(kVK_ANSI_A), [], characters: text)
  }

  private func lastQuery(_ fixture: Fixture) -> String? {
    fixture.surface.updatedQueries.last
  }

}
