import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

private func stroke(
  _ keyCode: Int,
  _ modifiers: NSEvent.ModifierFlags = [],
  repeating: Bool = false,
  characters: String = ""
) -> PanelKeystroke {
  PanelKeystroke(
    keyCode: UInt16(keyCode),
    modifiers: modifiers,
    isARepeat: repeating,
    characters: characters
  )
}

// MARK: - PanelLetterNavigationTests

/// The default letter keys moving the choice, seen from outside the presenter.
@MainActor
struct PanelLetterNavigationTests {
  /// Three downs and three command-held J presses land on the same row,
  /// and releasing Command commits that row.
  @Test
  func commandHeldJMovesLikeDown() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    for _ in 0 ..< 3 {
      _ = fixture.presenter.handleKeyStroke(stroke(kVK_DownArrow, .command))
    }
    let expected = fixture.presenter.selection.chosenID
    _ = fixture.presenter.handleKeyStroke(stroke(kVK_Escape))
    #expect(!fixture.surface.isPresented)
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    for _ in 0 ..< 3 {
      #expect(
        fixture.presenter.handleKeyStroke(stroke(kVK_ANSI_J, .command, characters: "j"))
          == .absorbed
      )
    }
    #expect(fixture.presenter.selection.chosenID == expected)
    fixture.presenter.handleCommandRelease()
    #expect(!fixture.surface.isPresented)
    let chosen = fixture.windows.first { $0.id == expected }
    #expect(chosen != nil)
    #expect(fixture.log.lines.contains(where: {
      $0.hasPrefix("committed ") && $0.contains(chosen!.displayTitle)
    }))
  }

  /// While filtering, letters type into the query whether or not Command
  /// is held. One press reads as one thing, so the query holding the
  /// letters shows they did not move the choice.
  @Test
  func lettersTypeWhileFiltering() {
    for modifiers in [NSEvent.ModifierFlags(), NSEvent.ModifierFlags.command] {
      let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
      fixture.presenter.handleHotkey(.filter, deliveryDelay: nil)
      for (code, character) in [
        (kVK_ANSI_J, "j"),
        (kVK_ANSI_K, "k"),
        (kVK_ANSI_N, "n"),
        (kVK_ANSI_P, "p"),
        (kVK_ANSI_S, "s"),
      ] {
        _ = fixture.presenter.handleKeyStroke(stroke(code, modifiers, characters: character))
      }
      #expect(fixture.surface.updatedQueries.last == "jknps")
    }
  }

  /// A pending number is dropped by a letter move, so a digit, a J and a
  /// digit name a single row rather than a two-digit number.
  @Test
  func pendingDigitsAreDroppedByLetterMoves() {
    let fixture = Fixture(entryCount: 12, closesOnCommandRelease: true)
    fixture.presenter.numberJump = true
    fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
    _ = fixture.presenter.handleKeyStroke(stroke(kVK_ANSI_1, .command, characters: "1"))
    _ = fixture.presenter.handleKeyStroke(stroke(kVK_ANSI_J, .command, characters: "j"))
    _ = fixture.presenter.handleKeyStroke(stroke(kVK_ANSI_3, .command, characters: "3"))
    #expect(fixture.presenter.selection.chosenID == fixture.windows[2].id)
  }
}
