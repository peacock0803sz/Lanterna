@testable import Lanterna
import Testing

struct KeyBindingCategoryTests {

  @Test
  func everyActionBelongsToExactlyOneCategory() {
    let grouped = KeyBindingCategory.allCases.flatMap(\.actions)
    #expect(grouped.count == KeyBindingAction.allCases.count)
    #expect(Set(grouped).count == grouped.count)
    for action in KeyBindingAction.allCases {
      #expect(grouped.contains(action))
    }
  }

  @Test
  func chainingCategoriesSpellsFileOrder() {
    #expect(KeyBindingCategory.allCases.flatMap(\.actions) == [
      .show,
      .showReverse,
      .showFilter,
      .next,
      .previous,
      .commit,
      .cancel,
      .toggleScope,
      .numberJump,
      .moveRowUp,
      .moveRowDown,
      .startFiltering,
      .deleteBackward,
      .clearQuery,
      .closeWindow,
      .quitApplication,
      .hideApplication,
      .minimizeWindow,
    ])
  }

  @Test
  func displayNamesMatchCurrentNames() {
    let names = KeyBindingAction.allCases.map(KeyBindingCategory.displayName(for:))
    #expect(names == [
      "Show",
      "Show in reverse",
      "Show for filtering",
      "Next",
      "Previous",
      "Commit",
      "Cancel",
      "Toggle active app only",
      "Delete backward",
      "Clear query",
      "Close window",
      "Quit application",
      "Hide application",
      "Minimize window",
      "Jump to row number",
      "Move row up",
      "Move row down",
      "Start filtering",
    ])
  }

  @Test
  func shortQueryFindsOnlySwitcher() {
    let found = KeyBindingCategory.matches("sh")
    #expect(found?.count == 1)
    #expect(found?.first?.category == .switcher)
    #expect(found?.first?.actions == [.show, .showReverse, .showFilter])
  }

  @Test
  func matchingIgnoresCase() {
    let lower = KeyBindingCategory.matches("sh")
    let upper = KeyBindingCategory.matches("SH")
    #expect(upper?.count == lower?.count)
    #expect(upper?.first?.actions == lower?.first?.actions)
  }

  @Test
  func blankTextIsNoSearch() {
    #expect(KeyBindingCategory.matches("  ") == nil)
    #expect(KeyBindingCategory.matches("") == nil)
  }

  @Test
  func unmatchedTextReadsAsEmptySearch() {
    #expect(KeyBindingCategory.matches("zzz")?.isEmpty == true)
  }

  @Test
  func broadQueryKeepsCategoryAndRowOrder() {
    let found = KeyBindingCategory.matches("ca") ?? []
    #expect(found.map(\.category) == [.navigation, .windowActions])
    #expect(found.map(\.actions) == [[.cancel], [.quitApplication, .hideApplication]])
  }

  @Test
  func queryRowsAreSearched() {
    let found = KeyBindingCategory.matches("cl") ?? []
    #expect(found.map(\.category) == [.query, .windowActions])
    #expect(found.map(\.actions) == [[.clearQuery], [.closeWindow]])
  }

  @Test
  func paddedQueryIsTrimmed() {
    let found = KeyBindingCategory.matches(" sh ")
    #expect(found?.map(\.category) == [.switcher])
    #expect(found?.first?.actions == [.show, .showReverse, .showFilter])
  }

}
