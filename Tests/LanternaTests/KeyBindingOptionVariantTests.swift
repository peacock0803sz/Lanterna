@testable import Lanterna
import Testing

// MARK: - KeyBindingOptionVariantTests

/// Names the pair a newly added default key overlaps.
///
/// The resolver already fails an overlapping default as a conflict, without
/// naming which two actions share the key. This test points at the pair and
/// the key, so adding a default key shows the existing default it collides with.
@MainActor
struct KeyBindingOptionVariantTests {

  @Test
  func defaultsShareNoKeyAcrossActions() {
    let table = KeyBindingTable.defaults
    let actions = KeyBindingAction.allCases
    for firstIndex in actions.indices {
      for secondIndex in actions.indices where secondIndex > firstIndex {
        let first = actions[firstIndex]
        let second = actions[secondIndex]
        guard !KeyBindingResolver.isExcusedPair(first, second) else { continue }
        let shared = Set(table[first]).intersection(table[second])
        for key in shared {
          Issue.record("\(first.rawValue) and \(second.rawValue) share \(key.displayName)")
        }
      }
    }
  }

}
