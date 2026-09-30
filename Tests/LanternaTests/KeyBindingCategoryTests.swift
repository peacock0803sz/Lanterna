@testable import Lanterna
import Testing

struct KeyBindingCategoryTests {

  // MARK: Internal

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
      "Delete backward",
      "Clear query",
      "Close window",
      "Quit application",
      "Hide application",
      "Minimize window",
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
    let found = KeyBindingCategory.matches("e") ?? []
    #expect(found.map(\.category) == found.map(\.category).sorted(by: { order(of: $0) < order(of: $1) }))
    for entry in found {
      #expect(entry.actions == entry.category.actions.filter { entry.actions.contains($0) })
    }
    #expect(found.flatMap(\.actions).count > 1)
  }

  // MARK: Private

  private func order(of category: KeyBindingCategory) -> Int {
    KeyBindingCategory.allCases.firstIndex(of: category) ?? 0
  }

}
