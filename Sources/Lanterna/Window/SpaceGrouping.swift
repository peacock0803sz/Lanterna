import CoreGraphics

// MARK: - SpaceGrouping

/// Which Space group each window of one pass joins, and what the group is
/// called. Nil throughout when the displays could not be read or none is
/// showing anything.
struct SpaceGrouping {

  // MARK: Internal

  let reading: SpaceReading
  let displayNames: [String: String]

  func group(of windowID: CGWindowID, appName: String) -> SpaceGroup? {
    guard
      let layout = reading.layout,
      let spaceID = layout.group(forWindowOn: reading.spaces[windowID] ?? []),
      let order = layout.groupOrder.firstIndex(of: spaceID)
    else {
      return nil
    }
    let heading = layout.heading(for: spaceID, displayNames: displayNames, fullscreenAppName: appName)
    return SpaceGroup(order: order, title: heading.title, detail: heading.detail)
  }

}
