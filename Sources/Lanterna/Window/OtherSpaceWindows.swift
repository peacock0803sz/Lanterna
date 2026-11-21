import CoreGraphics
import Foundation
import PrivateAPIs

// MARK: - OtherSpaceWindows

/// The windows the window server keeps on Spaces no display is showing, by
/// owning process.
///
/// Read from the window server alone, so it also names windows an
/// application's accessibility list leaves out. That is what makes it worth
/// reading: it says which windows are worth looking for, and a window found
/// some other way that is not here is hidden or closed rather than elsewhere.
/// Only the window number, owner and layer are read; never a title, which is
/// what keeps the Screen Recording permission out of it.
struct OtherSpaceWindows: Sendable, Equatable {

  /// One window-list entry, reduced to what the decision needs.
  struct Entry: Equatable {

    // MARK: Lifecycle

    init(windowID: CGWindowID, ownerProcessIdentifier: pid_t, layer: Int) {
      self.windowID = windowID
      self.ownerProcessIdentifier = ownerProcessIdentifier
      self.layer = layer
    }

    /// Nil when the entry lacks a number or an owner. A missing layer reads
    /// as not layer zero, so such an entry is never kept.
    init?(info: [String: Any]) {
      guard
        let number = info[kCGWindowNumber as String] as? NSNumber,
        let owner = info[kCGWindowOwnerPID as String] as? NSNumber
      else {
        return nil
      }
      self.init(
        windowID: number.uint32Value,
        ownerProcessIdentifier: owner.int32Value,
        layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
      )
    }

    // MARK: Internal

    let windowID: CGWindowID
    let ownerProcessIdentifier: pid_t
    let layer: Int

  }

  var windows = [pid_t: Set<CGWindowID>]()

  /// Layer-zero windows that are on at least one Space and on none any
  /// display is showing, by owner. With no shown Space known nothing can be
  /// compared, so the answer is empty.
  static func build(
    entries: [Entry],
    spaces: (CGWindowID) -> [CGSSpaceID],
    currentSpaces: Set<CGSSpaceID>
  ) -> OtherSpaceWindows {
    var result = OtherSpaceWindows()
    guard !currentSpaces.isEmpty else {
      return result
    }
    for entry in entries where entry.layer == 0 {
      if SpacePlacement.isOnOtherSpace(windowSpaces: spaces(entry.windowID), currentSpaces: currentSpaces) {
        result.windows[entry.ownerProcessIdentifier, default: []].insert(entry.windowID)
      }
    }
    return result
  }

  func windowIDs(of processIdentifier: pid_t) -> Set<CGWindowID> {
    windows[processIdentifier] ?? []
  }

}

// MARK: - WindowServerSpaceLocator + other Spaces

extension WindowServerSpaceLocator {
  /// One window list for every process, then one Space query per layer-zero
  /// window. The displays are read first: with none showing a known Space
  /// there is nothing to compare against and the list is not asked for.
  func otherSpaceWindows() -> OtherSpaceWindows {
    let connection = CGSMainConnectionID()
    let answer: CFArray? = CGSCopyManagedDisplaySpaces(connection)
    let currentSpaces = SpacePlacement.currentSpaces(from: answer as? [[String: Any]] ?? [])
    guard !currentSpaces.isEmpty else {
      return OtherSpaceWindows()
    }
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return .build(
      entries: list.compactMap(OtherSpaceWindows.Entry.init(info:)),
      spaces: { Self.spaces(of: $0, connection: connection) },
      currentSpaces: currentSpaces
    )
  }
}
