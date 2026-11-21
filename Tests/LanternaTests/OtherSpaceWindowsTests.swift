import CoreGraphics
import Foundation
@testable import Lanterna
import PrivateAPIs
import Testing

/// Which windows count as kept on a hidden Space, fed made-up window lists
/// and Space answers so nothing depends on this machine's desktops.
struct OtherSpaceWindowsTests {

  // MARK: Internal

  /// Windows on Spaces no display shows are kept, under their owner.
  @Test
  func windowsOnlyOnHiddenSpacesAreKeptByOwner() {
    let windows = OtherSpaceWindows.build(
      entries: [entry(10, owner: 1), entry(11, owner: 1), entry(20, owner: 2)],
      spaces: { [10: [5], 11: [6], 20: [5]][$0] ?? [] },
      currentSpaces: [7, 8]
    )

    #expect(windows.windowIDs(of: 1) == [10, 11])
    #expect(windows.windowIDs(of: 2) == [20])
  }

  /// Menu-bar strips and other windows off layer zero are not windows a
  /// row could stand for.
  @Test
  func windowsOffLayerZeroAreDropped() {
    let windows = OtherSpaceWindows.build(
      entries: [entry(10, owner: 1, layer: 25), entry(11, owner: 1)],
      spaces: { _ in [5] },
      currentSpaces: [7]
    )

    #expect(windows.windowIDs(of: 1) == [11])
  }

  /// A window on no Space at all, the shape of an unselected tab, a closed
  /// window the application keeps, or a panel it is not showing, is not
  /// elsewhere.
  @Test
  func windowsOnNoSpaceAreDropped() {
    let windows = OtherSpaceWindows.build(
      entries: [entry(10, owner: 1), entry(11, owner: 1)],
      spaces: { [11: [5]][$0] ?? [] },
      currentSpaces: [7]
    )

    #expect(windows.windowIDs(of: 1) == [11])
  }

  /// A window that is also on a Space some display shows is in view.
  @Test
  func windowsAlsoOnAShownSpaceAreDropped() {
    let windows = OtherSpaceWindows.build(
      entries: [entry(10, owner: 1), entry(11, owner: 1)],
      spaces: { [10: [5, 7], 11: [5]][$0] ?? [] },
      currentSpaces: [7]
    )

    #expect(windows.windowIDs(of: 1) == [11])
  }

  @Test
  func anOwnerWithNoSuchWindowHasNone() {
    let windows = OtherSpaceWindows.build(
      entries: [entry(10, owner: 1)],
      spaces: { _ in [5] },
      currentSpaces: [7]
    )

    #expect(windows.windowIDs(of: 2).isEmpty)
  }

  /// With no shown Space known nothing can be compared, so nothing is
  /// claimed to be elsewhere.
  @Test
  func noShownSpaceYieldsNothing() {
    let windows = OtherSpaceWindows.build(
      entries: [entry(10, owner: 1)],
      spaces: { _ in [5] },
      currentSpaces: []
    )

    #expect(windows == OtherSpaceWindows())
  }

  /// One window-list entry: its number, owner and layer, and nothing else.
  @Test
  func anEntryReadsNumberOwnerAndLayer() {
    let info: [String: Any] = [
      kCGWindowNumber as String: NSNumber(value: 42),
      kCGWindowOwnerPID as String: NSNumber(value: 512),
      kCGWindowLayer as String: NSNumber(value: 0),
    ]

    #expect(OtherSpaceWindows.Entry(info: info) == entry(42, owner: 512))
  }

  @Test
  func anEntryWithoutANumberOrOwnerIsSkipped() {
    let noNumber: [String: Any] = [kCGWindowOwnerPID as String: NSNumber(value: 512)]
    let noOwner: [String: Any] = [kCGWindowNumber as String: NSNumber(value: 42)]

    #expect(OtherSpaceWindows.Entry(info: noNumber) == nil)
    #expect(OtherSpaceWindows.Entry(info: noOwner) == nil)
  }

  // MARK: Private

  private func entry(_ windowID: CGWindowID, owner: pid_t, layer: Int = 0) -> OtherSpaceWindows.Entry {
    OtherSpaceWindows.Entry(windowID: windowID, ownerProcessIdentifier: owner, layer: layer)
  }

}
