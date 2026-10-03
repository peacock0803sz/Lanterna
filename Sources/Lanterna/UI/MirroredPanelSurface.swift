import AppKit
import Foundation

// MARK: - MirroredPanelSurface

/// Shows one appearance on every panel at once, with the same rows,
/// choice and query everywhere.
///
/// Only the cursor display's panel takes keys; the rest mirror what
/// it shows. Extra panels are made at startup for the connected
/// displays and kept across appearances; only a display-count change
/// grows or shrinks the pool, so appearing costs nothing it did not
/// already cost.
@MainActor
final class MirroredPanelSurface: SwitcherSurface {

  // MARK: Lifecycle

  init(
    panels: [any SwitcherSurface],
    keyResolver: DisplayResolver = DisplayResolver()
  ) {
    precondition(!panels.isEmpty, "mirroring needs at least one panel")
    self.panels = panels
    self.keyResolver = keyResolver
    _ = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.screensChanged()
      }
    }
  }

  // MARK: Internal

  /// The panel taking keys now, as an index into the panels. Refreshed
  /// on every appearance from the cursor display.
  private(set) var keyPanelIndex = 0

  /// Reads live display sources for the key panel choice. Replaced in
  /// tests.
  var keyResolver: DisplayResolver

  /// Makes the mirrors the pool needs. Set by the application wiring;
  /// without it the opening pool stands, which is the single-display
  /// case.
  var makeMirror: (@MainActor () -> SwitcherPanel)?

  /// The mirrors behind the primary panel, in display order.
  private(set) var mirrors = [SwitcherPanel]()

  var isPresented: Bool {
    panels.allSatisfy(\.isPresented)
  }

  var isTakingKeys: Bool {
    panels[keyPanelIndex].isTakingKeys
  }

  func present(windows: [WindowItem], selecting: WindowItem.Identifier?, filterActive: Bool = false) {
    refreshPool()
    refreshKeyPanel()
    for panel in panels {
      panel.present(windows: windows, selecting: selecting, filterActive: filterActive)
    }
    placeOnScreens(panels)
  }

  func takeKeys() -> Bool {
    panels[keyPanelIndex].takeKeys()
  }

  func showSelection(_ id: WindowItem.Identifier?) {
    for panel in panels {
      panel.showSelection(id)
    }
  }

  func showScope(_ band: ScopeBand?) {
    for panel in panels {
      panel.showScope(band)
    }
  }

  func showNotice(_ text: String) {
    for panel in panels {
      panel.showNotice(text)
    }
  }

  func clearNotice() {
    for panel in panels {
      panel.clearNotice()
    }
  }

  func updateList(
    windows: [WindowItem],
    selecting: WindowItem.Identifier?,
    query: String,
    filterActive: Bool
  ) {
    for panel in panels {
      panel.updateList(windows: windows, selecting: selecting, query: query, filterActive: filterActive)
    }
  }

  func dismiss() {
    for panel in panels {
      panel.dismiss()
    }
  }

  /// Brings the pool to the connected displays: one mirror per extra
  /// display. A shrinking pool takes its panels down first.
  func refreshPool() {
    guard let makeMirror else {
      return
    }
    let extra = max(NSScreen.screens.count - 1, 0)
    while mirrors.count < extra {
      let mirror = makeMirror()
      mirror.placesItself = false
      mirrors.append(mirror)
    }
    while mirrors.count > extra {
      mirrors.removeLast().orderOut(nil)
    }
    var grown: [any SwitcherSurface] = [panels[0]]
    grown.append(contentsOf: mirrors)
    panels = grown
    keyPanelIndex = min(keyPanelIndex, panels.count - 1)
  }

  /// Copies the content-affecting state onto the mirrors, so every
  /// panel sizes and filters alike. Placement stays with the caller:
  /// mirrors never place themselves.
  func syncMirrors(from primary: SwitcherPanel) {
    for mirror in mirrors {
      mirror.displayModes = primary.displayModes
      mirror.exclusionRules = primary.exclusionRules
      mirror.searchSettings = primary.searchSettings
      mirror.textScale = primary.textScale
      mirror.grouping = primary.grouping
      mirror.appearance = primary.appearance
    }
  }

  // MARK: Private

  private var panels: [any SwitcherSurface]

  /// Points keys at the cursor display's panel, clamped to the pool.
  private func refreshKeyPanel() {
    let resolved = keyResolver.resolve(.cursor)
    if case .single(let index) = resolved, panels.indices.contains(index) {
      keyPanelIndex = index
      return
    }
    keyPanelIndex = panels.startIndex
  }

  /// Centres each real panel on its display. Anything else in the pool
  /// was already placed by its own present.
  private func placeOnScreens(_ panels: [any SwitcherSurface]) {
    let screens = NSScreen.screens
    for (index, surface) in panels.enumerated() {
      guard screens.indices.contains(index), let panel = surface as? SwitcherPanel else {
        continue
      }
      panel.center(in: screens[index])
    }
  }

  /// Puts displayed panels back after the displays have been
  /// rearranged. A panel that is down needs nothing: the next
  /// appearance places it.
  private func screensChanged() {
    guard isPresented else { return }
    refreshPool()
    refreshKeyPanel()
    placeOnScreens(panels)
  }

}
