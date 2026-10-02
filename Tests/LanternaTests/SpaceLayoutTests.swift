import CoreGraphics
import Foundation
@testable import Lanterna
import PrivateAPIs
import Testing

// MARK: - SpaceLayoutTests

/// The displays and Spaces as read back from the window server's answer.
///
/// The fixture is the shape observed on three displays with two, one and
/// two desktops: displays in the order the server gave them, each with
/// its Spaces and the one it shows.
struct SpaceLayoutTests {

  // MARK: Internal

  /// Desktops are numbered per display, counting desktops only, and the
  /// Spaces keep the server's order.
  @Test
  func desktopsAreNumberedPerDisplay() {
    let layout = SpaceLayout.read(from: observed)
    #expect(layout.displays.map(\.identifier) == ["MAIN", "LCD", "BUILTIN"])
    #expect(layout.displays[0].spaces.map(\.desktopNumber) == [1, 2])
    #expect(layout.displays[2].spaces.map(\.id) == [29, 7])
    let withFullscreen = SpaceLayout.read(from: [display("A", current: 1, spaces: [(1, 0), (2, 4), (3, 0)])])
    let numbers: [Int?] = withFullscreen.displays[0].spaces.map(\.desktopNumber)
    #expect(numbers == [1, nil, 2])
  }

  /// Shown Spaces come first, display by display, then the rest in
  /// Mission Control order.
  @Test
  func shownSpacesLeadTheGroupOrder() {
    let layout = SpaceLayout.read(from: observed)
    #expect(layout.groupOrder == [4, 28, 7, 3, 29])
  }

  /// A window joins the first shown Space it is on, else its first Space
  /// in group order; everywhere or nowhere joins the first shown one.
  @Test
  func aWindowJoinsOneGroup() {
    let layout = SpaceLayout.read(from: observed)
    #expect(layout.group(forWindowOn: [3]) == 3)
    #expect(layout.group(forWindowOn: [29, 7]) == 7)
    #expect(layout.group(forWindowOn: [3, 29]) == 3)
    #expect(layout.group(forWindowOn: []) == 4)
    #expect(layout.group(forWindowOn: [3, 4, 28, 29, 7]) == 4)
    #expect(layout.group(forWindowOn: [999]) == 4)
  }

  /// Every window in a busy layout lands in exactly one group, and the
  /// group drawn first is a shown one.
  @Test
  func everyWindowLandsInExactlyOneGroup() {
    let layout = SpaceLayout.read(from: observed)
    let order = layout.groupOrder
    let shown = Set(layout.displays.compactMap(\.current))
    let windows: [[CGSSpaceID]] = (0 ..< 30).map { index in
      let all: [CGSSpaceID] = [3, 4, 28, 29, 7]
      return index % 7 == 0 ? [] : [all[index % all.count]]
    }
    for spaces in windows {
      let group = layout.group(forWindowOn: spaces)
      #expect(group.map { order.contains($0) } == true)
    }
    #expect(order.first.map(shown.contains) == true)
  }

  /// Headings name the desktop, the display when there is more than one,
  /// and whether it is shown; a display with no known name reads by its
  /// place, so two first desktops never read alike.
  @Test
  func headingsTellDisplaysApart() {
    let layout = SpaceLayout.read(from: observed)
    let names = ["MAIN": "Mi monitor", "LCD": "LCD-MQ271XD"]
    #expect(layout.heading(for: 4, displayNames: names, fullscreenAppName: nil) == ("Desktop 2", "Mi monitor · shown"))
    #expect(layout.heading(for: 3, displayNames: names, fullscreenAppName: nil) == ("Desktop 1", "Mi monitor"))
    #expect(layout.heading(for: 29, displayNames: names, fullscreenAppName: nil) == ("Desktop 1", "Display 3"))
    let single = SpaceLayout.read(from: [display("A", current: 1, spaces: [(1, 0), (2, 4)])])
    #expect(single.heading(for: 1, displayNames: [:], fullscreenAppName: nil) == ("Desktop 1", "shown"))
    let fullscreen = single.heading(for: 2, displayNames: [:], fullscreenAppName: "Safari")
    #expect(fullscreen.title == "Safari (Full Screen)")
    #expect(fullscreen.detail == nil)
  }

  /// No display showing anything leaves nothing to put first.
  @Test
  func nothingShownLeavesNoOrder() {
    let layout = SpaceLayout.read(from: [display("A", current: nil, spaces: [(1, 0)])])
    #expect(layout.groupOrder.isEmpty)
    #expect(layout.group(forWindowOn: [1]) == nil)
    #expect(SpaceLayout.read(from: []).groupOrder.isEmpty)
  }

  // MARK: Private

  /// The observed shape: the main display shows its second desktop.
  private var observed: [[String: Any]] {
    [
      display("MAIN", current: 4, spaces: [(3, 0), (4, 0)]),
      display("LCD", current: 28, spaces: [(28, 0)]),
      display("BUILTIN", current: 7, spaces: [(29, 0), (7, 0)]),
    ]
  }

  private func display(_ identifier: String, current: CGSSpaceID?, spaces: [(CGSSpaceID, Int)]) -> [String: Any] {
    var entry: [String: Any] = [
      "Display Identifier": identifier,
      "Spaces": spaces.map { ["id64": NSNumber(value: $0.0), "type": NSNumber(value: $0.1)] },
    ]
    if let current {
      entry["Current Space"] = ["id64": NSNumber(value: current)]
    }
    return entry
  }

}
