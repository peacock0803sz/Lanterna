import AppKit
@testable import Lanterna
import Testing

// MARK: - MRUTrackerStandInTests

/// A row standing for an application's windows elsewhere sorts by that
/// application's recorded use, the way a row for an application with no
/// window does: both are named by the process, not a window.
@MainActor
struct MRUTrackerStandInTests {

  @Test
  func aStandInSortsByItsApplicationsUse() {
    let tracker = MRUTracker()
    let window = WindowItem(
      id: .window(1),
      ownerProcessIdentifier: 101,
      appName: "Safari",
      bundleIdentifier: nil,
      windowTitle: "Start",
      kind: .standard,
      isMinimized: false,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
    let preview = WindowItem(
      id: .application(102),
      ownerProcessIdentifier: 102,
      appName: "Preview",
      bundleIdentifier: nil,
      windowTitle: "",
      kind: .standard,
      isMinimized: false,
      isOnOtherSpace: true,
      windowsElsewhere: 1,
      icon: NSImage(size: NSSize(width: 1, height: 1))
    )
    tracker.recordApplicationUse(102)

    #expect(tracker.arranged([window, preview]).map(\.id) == [preview.id, window.id])
  }

}
