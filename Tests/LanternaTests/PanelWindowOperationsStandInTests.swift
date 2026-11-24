import AppKit
@testable import Lanterna
import Testing

/// A row standing for an application's windows on other desktops.
@MainActor
private func standInRow(pid: pid_t = 321) -> WindowItem {
  WindowItem(
    id: .application(pid),
    ownerProcessIdentifier: pid,
    appName: "Preview",
    bundleIdentifier: "com.apple.Preview",
    windowTitle: "",
    kind: .standard,
    isMinimized: false,
    isOnOtherSpace: true,
    windowsElsewhere: 2,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - PanelWindowOperationsStandInTests

/// A stand-in row names no window it could reach, so the window operations
/// have nothing to act on; the panel says why, rather than claiming there
/// is no window. The application operations still apply.
@MainActor
struct PanelWindowOperationsStandInTests {

  @Test(arguments: [
    (WindowOperation.closeWindow, "Can't close a window on another desktop"),
    (.minimizeWindow, "Can't minimize a window on another desktop"),
  ])
  func aWindowOperationSaysTheWindowIsElsewhere(operation: WindowOperation, notice: String) async {
    let row = standInRow()
    let sent = SentCount()
    let made = makeOperations(
      rows: [row],
      close: { _ in
        sent.add()
        return nil
      },
      minimize: { _ in
        sent.add()
        return nil
      }
    )
    await made.operations.operate(operation, naming: row.id)
    #expect(sent.value == 0)
    #expect(made.surface.notices == [notice])
    #expect(made.surface.updatedLists.isEmpty)
  }

  @Test
  func hidingReachesTheApplication() async {
    let row = standInRow(pid: 654)
    let hidden = SentCount()
    let made = makeOperations(
      rows: [row],
      refreshed: [],
      hide: { pid in
        if pid == 654 {
          hidden.add()
        }
        return nil
      }
    )
    await made.operations.operate(.hideApplication, naming: row.id)
    #expect(hidden.value == 1)
    #expect(made.surface.notices.isEmpty)
  }

  @Test
  func quittingReachesTheApplication() async {
    let row = standInRow(pid: 654)
    let quit = SentCount()
    let made = makeOperations(
      rows: [row],
      refreshed: [],
      quit: { pid in
        if pid == 654 {
          quit.add()
        }
        return nil
      }
    )
    await made.operations.operate(.quitApplication, naming: row.id)
    #expect(quit.value == 1)
  }

}
