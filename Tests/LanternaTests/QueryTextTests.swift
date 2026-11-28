import Testing
@testable import Lanterna

// MARK: - QueryTextTests

/// The query value on its own: inserting, moving, and deleting around
/// an insertion point, without any panel behind it.
struct QueryTextTests {

  @Test
  func insertingLandsAtTheInsertionPoint() {
    var line = QueryText(text: "safri", cursor: 3)
    line.insert("a")
    #expect(line == QueryText(text: "safari", cursor: 4))
  }

  @Test
  func insertingAtTheStartAndEnd() {
    var line = QueryText()
    line.insert("ab")
    #expect(line == QueryText(text: "ab", cursor: 2))
    var start = QueryText(text: "cd", cursor: 0)
    start.insert("ab")
    #expect(start == QueryText(text: "abcd", cursor: 2))
  }

  @Test
  func insertingNothingChangesNothing() {
    var line = QueryText(text: "ab", cursor: 1)
    line.insert("")
    #expect(line == QueryText(text: "ab", cursor: 1))
  }

  @Test
  func confirmedTextLandsWholeAndMovesPast() {
    var line = QueryText(text: "foo", cursor: 3)
    line.insert("bar")
    #expect(line == QueryText(text: "foobar", cursor: 6))
  }

  @Test
  func movingStepsOneCharacter() {
    var line = QueryText(text: "safari", cursor: 6)
    #expect(line.apply(.moveLeft) == false)
    #expect(line.cursor == 5)
    #expect(line.apply(.moveRight) == false)
    #expect(line.cursor == 6)
  }

  @Test
  func movingToTheEnds() {
    var line = QueryText(text: "safari", cursor: 3)
    #expect(line.apply(.moveToStart) == false)
    #expect(line.cursor == 0)
    #expect(line.apply(.moveToEnd) == false)
    #expect(line.cursor == 6)
  }

  @Test
  func movingPastTheEndsDoesNothing() {
    var start = QueryText(text: "ab", cursor: 0)
    #expect(start.apply(.moveLeft) == false)
    #expect(start.cursor == 0)
    var end = QueryText(text: "ab", cursor: 2)
    #expect(end.apply(.moveRight) == false)
    #expect(end.cursor == 2)
  }

  @Test
  func deletingBackwardRemovesTheCharacterBefore() {
    var line = QueryText(text: "safarx", cursor: 6)
    #expect(line.apply(.deleteBackward) == true)
    #expect(line == QueryText(text: "safar", cursor: 5))
  }

  @Test
  func deletingBackwardAtTheStartDoesNothing() {
    var line = QueryText()
    #expect(line.apply(.deleteBackward) == false)
    #expect(line == QueryText())
  }

  @Test
  func deletingForwardRemovesTheCharacterAfter() {
    var line = QueryText(text: "safxari", cursor: 3)
    #expect(line.apply(.deleteForward) == true)
    #expect(line == QueryText(text: "safari", cursor: 3))
  }

  @Test
  func deletingForwardAtTheEndDoesNothing() {
    var line = QueryText(text: "ab", cursor: 2)
    #expect(line.apply(.deleteForward) == false)
    #expect(line == QueryText(text: "ab", cursor: 2))
  }

  @Test
  func deletingToTheStartClearsBefore() {
    var line = QueryText(text: "xxsafari", cursor: 2)
    #expect(line.apply(.deleteToStart) == true)
    #expect(line == QueryText(text: "safari", cursor: 0))
  }

  @Test
  func deletingToTheEndClearsAfter() {
    var line = QueryText(text: "safari window", cursor: 6)
    #expect(line.apply(.deleteToEnd) == true)
    #expect(line == QueryText(text: "safari", cursor: 6))
  }

  @Test
  func deletingAnEmptySideDoesNothing() {
    var start = QueryText(text: "ab", cursor: 0)
    #expect(start.apply(.deleteToStart) == false)
    var end = QueryText(text: "ab", cursor: 2)
    #expect(end.apply(.deleteToEnd) == false)
    #expect(start == QueryText(text: "ab", cursor: 0))
    #expect(end == QueryText(text: "ab", cursor: 2))
  }

  @Test
  func deletingAWordStopsAtSymbols() {
    var line = QueryText(text: "google chrome", cursor: 13)
    #expect(line.apply(.deleteWordBackward) == true)
    #expect(line == QueryText(text: "google ", cursor: 7))
    #expect(line.apply(.deleteWordBackward) == true)
    #expect(line == QueryText())
  }

  @Test
  func deletingAWordSkipsDividersFirst() {
    var line = QueryText(text: "foo.bar", cursor: 7)
    #expect(line.apply(.deleteWordBackward) == true)
    #expect(line == QueryText(text: "foo.", cursor: 4))
    #expect(line.apply(.deleteWordBackward) == true)
    #expect(line == QueryText())
  }

  @Test
  func deletingAWordKeepsWhatStandsAfter() {
    var line = QueryText(text: "ab cd", cursor: 2)
    #expect(line.apply(.deleteWordBackward) == true)
    #expect(line == QueryText(text: " cd", cursor: 0))
  }

  @Test
  func deletingAWordTreatsKanaAndKanjiAsWordCharacters() {
    var line = QueryText(text: "さふぁり りんご", cursor: 8)
    #expect(line.apply(.deleteWordBackward) == true)
    #expect(line == QueryText(text: "さふぁり ", cursor: 5))
  }

  @Test
  func deletingAWordTreatsFullWidthSpaceAsDivider() {
    var line = QueryText(text: "あいう\u{3000}えお", cursor: 6)
    #expect(line.apply(.deleteWordBackward) == true)
    #expect(line == QueryText(text: "あいう\u{3000}", cursor: 4))
  }

  @Test
  func deletingAWordOnLettersOnlyClearsToTheStart() {
    var line = QueryText(text: "saf", cursor: 3)
    #expect(line.apply(.deleteWordBackward) == true)
    #expect(line == QueryText())
  }

  @Test
  func deletingAWordWithNothingBeforeDoesNothing() {
    var line = QueryText(text: "ab", cursor: 0)
    #expect(line.apply(.deleteWordBackward) == false)
    #expect(line == QueryText(text: "ab", cursor: 0))
  }

  @Test
  func emojiAndCombiningMarksStayWhole() {
    var line = QueryText(text: "a👨‍👩‍👧b", cursor: 3)
    #expect(line.apply(.moveLeft) == false)
    #expect(line.cursor == 2)
    #expect(line.apply(.deleteBackward) == true)
    #expect(line == QueryText(text: "ab", cursor: 1))
    var combining = QueryText(text: "e\u{301}x", cursor: 1)
    #expect(combining.apply(.deleteBackward) == true)
    #expect(combining == QueryText(text: "x", cursor: 0))
  }

}
