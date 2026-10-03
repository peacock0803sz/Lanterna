import CoreGraphics
import Foundation

// MARK: - DisplayTarget

/// Which display the switcher panel opens on.
///
/// Mirrors the config file values (`"primary"`, `"cursor"`,
/// `"frontWindow"`, `"all"`). An absent key means `primary`: unless the
/// file says otherwise, the panel opens centred on the display that
/// carries the menu bar, exactly as before.
enum DisplayTarget: String, Sendable {
  /// The display that carries the menu bar.
  case primary
  /// The display under the mouse cursor when the panel opens.
  case cursor
  /// The display holding the focused window of the frontmost
  /// application when the panel opens.
  case frontWindow
  /// Every connected display at once.
  case all

  // MARK: Internal

  /// The target for one run: a spelled target wins, anything missing
  /// means the menu-bar display.
  static func effective(from config: ValidConfiguration) -> DisplayTarget {
    config.displayTarget ?? .primary
  }

  /// Picks the display for one appearance from plain values, so the
  /// choice reads as a value test with no window server involved. The
  /// points and frames share the Cocoa base coordinate space, which is
  /// what both the cursor position and the screen frames use.
  static func resolve(
    _ target: DisplayTarget,
    cursor: CGPoint?,
    focusedWindow: CGPoint?,
    screens: [DisplayInfo]
  ) -> ResolvedDisplay {
    precondition(!screens.isEmpty, "screens must hold at least one display")
    switch target {
    case .primary:
      return .single(primaryIndex(in: screens))
    case .cursor:
      return .single(index(of: cursor, in: screens))
    case .frontWindow:
      return .single(index(of: focusedWindow, in: screens))
    case .all:
      return .all(Array(screens.indices))
    }
  }

  // MARK: Private

  /// The menu-bar display, or the first screen when none claims it.
  private static func primaryIndex(in screens: [DisplayInfo]) -> Int {
    screens.firstIndex(where: \.isPrimary) ?? screens.startIndex
  }

  /// The screen holding this point, or the primary one when the point
  /// is missing or held by no screen.
  private static func index(of point: CGPoint?, in screens: [DisplayInfo]) -> Int {
    guard let point else {
      return primaryIndex(in: screens)
    }
    return screens.firstIndex(where: { $0.frame.contains(point) })
      ?? primaryIndex(in: screens)
  }
}

// MARK: - DisplayInfo

/// One display as the resolution sees it: its frame and whether it
/// carries the menu bar. Window-server objects stay outside so the
/// resolution answers from values alone.
struct DisplayInfo: Equatable, Sendable {
  var frame: CGRect
  var isPrimary: Bool
}

// MARK: - ResolvedDisplay

/// Where one appearance goes: one display, or every display at once.
enum ResolvedDisplay: Equatable, Sendable {
  /// One display, as an index into the screens the call resolved over.
  case single(Int)
  /// Every display, as indices into the same screens.
  case all([Int])
}
