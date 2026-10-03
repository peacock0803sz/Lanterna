import AppKit
@testable import Lanterna
import Testing

// MARK: - ManualRowOrderTests

/// How a hand-arranged order merges over the order rows would otherwise
/// draw in. Named rows come first in the stored order; rows the override
/// does not name keep their places after them, so a new window neither
/// vanishes nor scrambles what was arranged.
struct ManualRowOrderTests {

  // MARK: Internal

  @Test
  func noOverrideKeepsTheGivenOrder() {
    let rows = Fixture.rows(["a", "b", "c"])
    #expect(ManualRowOrder.none.applying(keys: [], to: rows).map(\.windowTitle) == ["a", "b", "c"])
  }

  @Test
  func namedRowsComeFirstInTheStoredOrder() {
    let rows = Fixture.rows(["a", "b", "c"])
    let order = ManualRowOrder(entries: [
      RowOrderEntry(group: 1, keys: [Fixture.key("c"), Fixture.key("a")])
    ])
    let arranged = order.applying(keys: order.keys(forGroup: 1) ?? [], to: rows)
    #expect(arranged.map(\.windowTitle) == ["c", "a", "b"])
  }

  @Test
  func namesMatchingNothingAreIgnored() {
    let rows = Fixture.rows(["a", "b"])
    let order = ManualRowOrder(entries: [
      RowOrderEntry(group: 1, keys: [Fixture.key("gone"), Fixture.key("b")])
    ])
    let arranged = order.applying(keys: order.keys(forGroup: 1) ?? [], to: rows)
    #expect(arranged.map(\.windowTitle) == ["b", "a"])
  }

  @Test
  func groupWithoutOverrideKeepsTheGivenOrder() {
    let rows = Fixture.rows(["a", "b"])
    let order = ManualRowOrder(entries: [
      RowOrderEntry(group: 2, keys: [Fixture.key("b")])
    ])
    #expect(order.keys(forGroup: 1) == nil)
    let arranged = order.applying(keys: order.keys(forGroup: 1) ?? [], to: rows)
    #expect(arranged.map(\.windowTitle) == ["a", "b"])
  }

  // MARK: Private

  /// Window rows named by title alone, all sharing one owner.
  private enum Fixture {
    static func key(_ title: String) -> RowKey {
      RowKey(owner: "com.example.app", title: title)
    }

    static func rows(_ titles: [String]) -> [WindowItem] {
      titles.enumerated().map { index, title in
        WindowItem(
          id: WindowItem.Identifier(windowID: CGWindowID(index + 1)),
          ownerProcessIdentifier: 100,
          appName: "Example",
          bundleIdentifier: "com.example.app",
          windowTitle: title,
          kind: .standard,
          isMinimized: false,
          icon: NSImage()
        )
      }
    }
  }

}
