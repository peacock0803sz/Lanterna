import AppKit
@testable import Lanterna
import Logging
import Testing

/// Rows with distinct names, so which rows leave is decided by the test.
@MainActor
private func appearanceRow(appName: String, windowTitle: String, windowID: CGWindowID) -> WindowItem {
  WindowItem(
    id: WindowItem.Identifier(windowID: windowID),
    ownerProcessIdentifier: 0,
    appName: appName,
    bundleIdentifier: nil,
    windowTitle: windowTitle,
    kind: .standard,
    isMinimized: false,
    icon: NSImage(size: NSSize(width: 1, height: 1))
  )
}

// MARK: - ExclusionAppearanceTests

/// What one appearance reports about exclusions.
///
/// Split out the way the log-level suite splits long suites: the filter
/// suite reached the body-length limit, so the appearance report lives
/// here instead.
@MainActor
struct ExclusionAppearanceTests {

  // MARK: Internal

  /// An appearance reports how many rows exclusions kept out, below the
  /// default threshold so an ordinary run stays quiet.
  @Test
  func appearanceReportsExcludedCount() {
    let surface = FakeSurface()
    surface.isPresented = true
    let log = DiagnosticsLog()
    let selection = PanelSelection(surface: surface)
    let filter = PanelFilter(selection: selection, surface: surface)
    filter.writeLine = { log.write($0, $1) }
    filter.exclusionRules = WindowExclusion.compile([
      ExclusionEntry(app: "^Safari$", titlePattern: "Update")
    ]).rules
    selection.beginSecond(rows.map(\.id))
    filter.begin(fullWindows: rows, filtering: false)
    #expect(filter.shownWindows.map(\.id) == [rows[1].id, rows[2].id])
    #expect(log.entries.contains { $0.level == .info && $0.line == "excluded 1 of 3 windows" })
  }

  // MARK: Private

  private var rows: [WindowItem] {
    [
      appearanceRow(appName: "Safari", windowTitle: "Update available", windowID: 1),
      appearanceRow(appName: "Safari", windowTitle: "Downloads folder", windowID: 2),
      appearanceRow(appName: "Finder", windowTitle: "Applications", windowID: 3),
    ]
  }

}
