import AppKit
@testable import Lanterna
import Testing

/// A running application with no window, as a row.
@MainActor
private func windowlessRow(pid: pid_t = 321) -> WindowItem {
  WindowItem(
    id: .application(pid),
    ownerProcessIdentifier: pid,
    appName: "Music",
    bundleIdentifier: "com.apple.Music",
    windowTitle: "",
    kind: .standard,
    isMinimized: false,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - PanelWindowOperationsWindowlessTests

/// An application row has no window, so the window operations have
/// nothing to act on, while the application operations still apply.
@MainActor
struct PanelWindowOperationsWindowlessTests {

  /// Closing or minimizing sends nothing and says so on the panel.
  @Test(arguments: [
    (WindowOperation.closeWindow, "No window to close"),
    (.minimizeWindow, "No window to minimize"),
  ])
  func aWindowOperationSaysThereIsNoWindow(operation: WindowOperation, notice: String) async {
    let row = windowlessRow()
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

  /// Quitting acts on the application the row stands for.
  @Test
  func quittingReachesTheApplication() async {
    let row = windowlessRow(pid: 654)
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
