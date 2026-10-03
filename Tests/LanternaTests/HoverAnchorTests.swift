import CoreGraphics
@testable import Lanterna
import Testing

// MARK: - HoverAnchorTests

/// Whether an arriving hover counts, decided against the snapshot taken
/// when the panel went up.
///
/// A panel opens under the pointer more often than not, and the first
/// hover arrives without the pointer having moved at all. Treating that
/// arrival as a choice would throw the opening selection away on every
/// appearance the pointer happened to cover. What is settled here is
/// the only rule: while the pointer sits where it sat, hovers are
/// dropped; once it moved, they count.
struct HoverAnchorTests {

  // MARK: Internal

  @Test
  func aHoverWhereThePointerSatIsDropped() {
    let anchor = HoverAnchor(point: CGPoint(x: 100, y: 200))
    #expect(anchor.shouldIgnore(current: CGPoint(x: 100, y: 200)) == true)
  }

  @Test
  func aHoverAfterAnyMoveCounts() {
    let anchor = HoverAnchor(point: CGPoint(x: 100, y: 200))
    #expect(anchor.shouldIgnore(current: CGPoint(x: 101, y: 200)) == false)
    #expect(anchor.shouldIgnore(current: CGPoint(x: 100, y: 201)) == false)
  }

}
