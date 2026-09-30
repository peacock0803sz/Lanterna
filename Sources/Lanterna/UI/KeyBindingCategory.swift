/// One settings group behind the keyboard sidebar.
///
/// Every action belongs to exactly one category, and chaining the
/// categories in order spells the file action order.
enum KeyBindingCategory: CaseIterable, Equatable, Hashable, Sendable {
  case switcher
  case navigation
  case query
  case windowActions

  // MARK: Internal

  /// The name the sidebar and the detail heading read.
  var title: String {
    switch self {
    case .switcher: "Switcher"
    case .navigation: "Navigation"
    case .query: "Query"
    case .windowActions: "Window actions"
    }
  }

  /// The symbol drawn beside the category name.
  var iconName: String {
    switch self {
    case .switcher: "rectangle.stack"
    case .navigation: "arrow.up.arrow.down"
    case .query: "character.cursor.ibeam"
    case .windowActions: "macwindow"
    }
  }

  /// The actions under the category, in file order.
  var actions: [KeyBindingAction] {
    switch self {
    case .switcher: [.show, .showReverse, .showFilter]
    case .navigation: [.next, .previous, .commit, .cancel]
    case .query: [.deleteBackward, .clearQuery]
    case .windowActions: [.closeWindow, .quitApplication, .hideApplication, .minimizeWindow]
    }
  }

  /// The row name for an action, matching the names users already read.
  static func displayName(for action: KeyBindingAction) -> String {
    switch action {
    case .show: "Show"
    case .showReverse: "Show in reverse"
    case .showFilter: "Show for filtering"
    case .next: "Next"
    case .previous: "Previous"
    case .commit: "Commit"
    case .cancel: "Cancel"
    case .deleteBackward: "Delete backward"
    case .clearQuery: "Clear query"
    case .closeWindow: "Close window"
    case .quitApplication: "Quit application"
    case .hideApplication: "Hide application"
    case .minimizeWindow: "Minimize window"
    }
  }

  /// The categories holding a name match, leaving out the rest.
  ///
  /// Blank text is no search at all, while text with no match reads as
  /// an empty search. Matching ignores case and keeps category order.
  static func matches(_ query: String) -> [(category: KeyBindingCategory, actions: [KeyBindingAction])]? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lowered = trimmed.lowercased()
    return allCases.compactMap { category -> (category: KeyBindingCategory, actions: [KeyBindingAction])? in
      let hits = category.actions.filter { displayName(for: $0).lowercased().contains(lowered) }
      guard !hits.isEmpty else { return nil }
      return (category, hits)
    }
  }
}
