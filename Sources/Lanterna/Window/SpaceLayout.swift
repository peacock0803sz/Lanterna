import CoreGraphics
import Foundation
import PrivateAPIs

// MARK: - SpaceLayout

/// The displays and their Spaces, as the window server lists them.
///
/// Read from the dictionaries `CGSCopyManagedDisplaySpaces` answers with:
/// displays in the order it gives them, and each display's Spaces in
/// Mission Control order, which reordering the desktops was seen to move.
/// The decisions about which group a window joins and what a group is
/// called live here, apart from the window server, so they can be held to
/// without one.
struct SpaceLayout: Equatable, Sendable {

  /// One Space of one display.
  struct Space: Equatable, Sendable {
    let id: CGSSpaceID
    let isFullscreen: Bool
    /// The desktop's number on its display, counting desktops only, the
    /// way Mission Control names them. Nil for a fullscreen Space.
    let desktopNumber: Int?
  }

  /// One display and its Spaces.
  struct Display: Equatable, Sendable {
    let identifier: String
    let spaces: [Space]
    let current: CGSSpaceID?
  }

  let displays: [Display]

  /// The order groups draw in: every shown Space, display by display, then
  /// every Space no display is showing, display by display in Mission
  /// Control order. Empty when no display reads as showing anything, which
  /// is when nothing can be put first.
  var groupOrder: [CGSSpaceID] {
    let shown = displays.compactMap(\.current)
    guard !shown.isEmpty else { return [] }
    let rest = displays.flatMap { display in
      display.spaces.map(\.id).filter { $0 != display.current }
    }
    return shown + rest
  }

  /// Reads the window server's answer. A Space or display entry that
  /// cannot be read is left out rather than guessed at.
  static func read(from displays: [[String: Any]]) -> SpaceLayout {
    SpaceLayout(displays: displays.compactMap { entry in
      guard let identifier = entry["Display Identifier"] as? String else { return nil }
      let current = ((entry["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value
      var desktops = 0
      let spaces = ((entry["Spaces"] as? [[String: Any]]) ?? []).compactMap { space -> Space? in
        guard let id = (space["id64"] as? NSNumber)?.uint64Value else { return nil }
        let isFullscreen = (space["type"] as? NSNumber)?.intValue == 4
        if !isFullscreen {
          desktops += 1
        }
        return Space(id: id, isFullscreen: isFullscreen, desktopNumber: isFullscreen ? nil : desktops)
      }
      return Display(identifier: identifier, spaces: spaces, current: current)
    })
  }

  /// The Space whose group a window joins, given the Spaces it is on.
  ///
  /// A window on several Spaces joins the first of them that is shown,
  /// in display order, else the first in group order. A window on every
  /// Space, or one the server says nothing about, joins the first shown
  /// Space: missing information never sends a row away. Nil only when
  /// nothing is shown, which leaves every row in one group.
  func group(forWindowOn windowSpaces: [CGSSpaceID]) -> CGSSpaceID? {
    let order = groupOrder
    guard let first = order.first else { return nil }
    let onSpaces = Set(windowSpaces)
    let known = Set(displays.flatMap { $0.spaces.map(\.id) })
    if onSpaces.isEmpty || known.isSubset(of: onSpaces) {
      return first
    }
    return order.first { onSpaces.contains($0) } ?? first
  }

  /// What a group's heading says: which Space, and — with more than one
  /// display — which display, and whether it is shown.
  ///
  /// A desktop reads as Mission Control names it. A fullscreen Space takes
  /// the name of the application filling it, which only the rows know.
  func heading(
    for spaceID: CGSSpaceID,
    displayNames: [String: String],
    fullscreenAppName: String?
  ) -> (title: String, detail: String?) {
    guard
      let displayIndex = displays.firstIndex(where: { $0.spaces.contains { $0.id == spaceID } }),
      let space = displays[displayIndex].spaces.first(where: { $0.id == spaceID })
    else {
      return ("Desktop", nil)
    }
    let display = displays[displayIndex]
    let title =
      if let number = space.desktopNumber {
        "Desktop \(number)"
      } else {
        "\(fullscreenAppName ?? "App") (Full Screen)"
      }
    var details = [String]()
    if displays.count > 1 {
      details.append(displayNames[display.identifier] ?? "Display \(displayIndex + 1)")
    }
    if display.current == spaceID {
      details.append("shown")
    }
    return (title, details.isEmpty ? nil : details.joined(separator: " · "))
  }

}
