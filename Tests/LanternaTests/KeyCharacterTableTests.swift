@testable import Lanterna
import Testing

// MARK: - KeyCharacterTableTests

/// The table Fast Search reads its letters from: one ASCII letter or digit
/// per key and Shift state, and nothing for a key that types anything else.
struct KeyCharacterTableTests {

  // MARK: Internal

  @Test
  func lettersAndDigitsAreKeptForBothShiftStates() {
    let table = KeyCharacterTable(translating: usLike)
    #expect(table.character(keyCode: 0, shift: false) == "a")
    #expect(table.character(keyCode: 0, shift: true) == "A")
    #expect(table.character(keyCode: 20, shift: false) == "3")
  }

  @Test
  func aShiftedSymbolIsNotKept() {
    let table = KeyCharacterTable(translating: usLike)
    #expect(table.character(keyCode: 20, shift: true) == nil)
  }

  @Test
  func keysThatTypeNoLetterOrDigitHaveNothing() {
    let table = KeyCharacterTable(translating: usLike)
    #expect(table.character(keyCode: 49, shift: false) == nil)
    #expect(table.character(keyCode: 41, shift: false) == nil)
    #expect(table.character(keyCode: 31, shift: false) == nil)
    #expect(table.character(keyCode: 32, shift: false) == nil)
    #expect(table.character(keyCode: 200, shift: false) == nil)
  }

  @Test
  func theEmptyTableHasNothing() {
    #expect(KeyCharacterTable.empty.character(keyCode: 0, shift: false) == nil)
  }

  // MARK: Private

  /// A US-like layout with the cases the table has to refuse: a symbol, a
  /// non-ASCII letter, two characters at once, and a key with no output.
  private func usLike(keyCode: UInt16, shift: Bool) -> String? {
    switch keyCode {
    case 0: shift ? "A" : "a"
    case 20: shift ? "#" : "3"
    case 41: ";"
    case 31: "ß"
    case 32: "ab"
    case 49: " "
    default: nil
    }
  }

}

// MARK: - KeyCharacterTableWatchTests

/// The watch hands over a table as it starts and on every refresh, and
/// nothing once stopped.
@MainActor
struct KeyCharacterTableWatchTests {

  // MARK: Internal

  @Test
  func startHandsOverTheCurrentTableAndRefreshHandsOverTheNextOne() {
    var tables = [KeyCharacterTable.empty, Self.oneKey]
    let watch = KeyCharacterTableWatch(read: { tables.removeFirst() })
    var received = [KeyCharacterTable]()

    watch.start { received.append($0) }
    watch.refresh()

    #expect(received == [.empty, Self.oneKey])
  }

  @Test
  func aStoppedWatchHandsOverNothing() {
    let watch = KeyCharacterTableWatch(read: { .empty })
    var received = 0
    watch.start { _ in received += 1 }
    watch.stop()
    watch.refresh()

    #expect(received == 1)
  }

  // MARK: Private

  private static let oneKey = KeyCharacterTable { keyCode, _ in keyCode == 0 ? "a" : nil }

}
