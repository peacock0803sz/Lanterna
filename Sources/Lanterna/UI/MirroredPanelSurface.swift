import AppKit
import Foundation

// MARK: - MirroredPanelSurface

/// Shows one appearance across the chosen panels, with the same rows,
/// choice and query everywhere.
///
/// The every-display choice shows on all panels at once, and only the
/// cursor display's panel takes keys while the rest mirror what it
/// shows; any other choice shows on the primary panel alone, which
/// takes the keys. Extra panels are made at startup for the connected
/// displays and kept across appearances; only a display-count change
/// grows or shrinks the pool, so an appearance builds no window.
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

  /// Which display rule the composite follows. Only the every-display
  /// choice fans out; anything else shows the primary panel alone.
  var displayTarget = DisplayTarget.primary

  /// Reads live display sources for the key panel choice. Replaced in
  /// tests.
  var keyResolver: DisplayResolver

  /// Makes the mirrors the pool needs. Set by the application wiring;
  /// without it the opening pool stands, which is the single-display
  /// case.
  var makeMirror: (@MainActor () -> SwitcherPanel)?

  /// The mirrors behind the primary panel, in display order.
  private(set) var mirrors = [SwitcherPanel]()

  /// Where a row hover goes. Stored here and fanned out to every
  /// panel, so mirrors made later hear the same handler.
  var onHoverRow: ((WindowItem.Identifier) -> Void)? {
    didSet { fanOutPointerHandlers() }
  }

  /// Where a row click goes. Same storage as the hover handler above.
  var onClickRow: ((WindowItem.Identifier) -> Void)? {
    didSet { fanOutPointerHandlers() }
  }

  /// Where a scroll step goes. Same storage as the handlers above.
  var onScrollStep: ((Int) -> Void)? {
    didSet { fanOutPointerHandlers() }
  }

  /// The panels one appearance touches: every panel for the
  /// every-display choice, otherwise only the primary one.
  var activePanels: [any SwitcherSurface] {
    displayTarget == .all ? panels : [panels[0]]
  }

  var isPresented: Bool {
    activePanels.allSatisfy(\.isPresented)
  }

  var isTakingKeys: Bool {
    if displayTarget == .all {
      return activePanels[keyPanelIndex].isTakingKeys
    }
    return activePanels[0].isTakingKeys
  }

  var appearanceHints: HintsMode {
    if displayTarget == .all {
      return activePanels[keyPanelIndex].appearanceHints
    }
    return activePanels[0].appearanceHints
  }

  func present(windows: [WindowItem], selecting: WindowItem.Identifier?, filterActive: Bool = false) {
    refreshPool()
    refreshKeyPanel()
    assignScreens()
    for panel in activePanels {
      panel.present(windows: windows, selecting: selecting, filterActive: filterActive)
    }
  }

  func takeKeys() -> Bool {
    if displayTarget == .all {
      return activePanels[keyPanelIndex].takeKeys()
    }
    return activePanels[0].takeKeys()
  }

  func showSelection(_ id: WindowItem.Identifier?) {
    for panel in activePanels {
      panel.showSelection(id)
    }
  }

  func showScope(_ band: ScopeBand?) {
    for panel in activePanels {
      panel.showScope(band)
    }
  }

  func showNumberedRows(_ ids: [WindowItem.Identifier]) {
    for panel in activePanels {
      panel.showNumberedRows(ids)
    }
  }

  func showNotice(_ text: String) {
    for panel in activePanels {
      panel.showNotice(text)
    }
  }

  func clearNotice() {
    for panel in activePanels {
      panel.clearNotice()
    }
  }

  func updateList(
    windows: [WindowItem],
    selecting: WindowItem.Identifier?,
    query: String,
    filterActive: Bool
  ) {
    for panel in activePanels {
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
      mirrors.append(makeMirror())
    }
    while mirrors.count > extra {
      mirrors.removeLast().orderOut(nil)
    }
    var grown: [any SwitcherSurface] = [panels[0]]
    grown.append(contentsOf: mirrors)
    panels = grown
    // Late mirrors start from startup values, so bring them up to the live settings.
    if let primary = panels[0] as? SwitcherPanel {
      syncMirrors(from: primary)
    }
    keyPanelIndex = min(keyPanelIndex, panels.count - 1)
  }

  /// Copies the content-affecting state onto the mirrors, so every
  /// panel sizes and filters alike. Which display each panel sits on is
  /// handed out on `present`, not copied.
  func syncMirrors(from primary: SwitcherPanel) {
    for mirror in mirrors {
      mirror.displayModes = primary.displayModes
      mirror.exclusionRules = primary.exclusionRules
      mirror.searchSettings = primary.searchSettings
      mirror.textScale = primary.textScale
      mirror.panelWidth = primary.panelWidth
      mirror.hoverSelect = primary.hoverSelect
      mirror.scrollSelect = primary.scrollSelect
      mirror.hintsMode = primary.hintsMode
      mirror.onHoverRow = primary.onHoverRow
      mirror.onClickRow = primary.onClickRow
      mirror.onScrollStep = primary.onScrollStep
      mirror.grouping = primary.grouping
      mirror.appearance = primary.appearance
    }
  }

  // MARK: Private

  private var panels: [any SwitcherSurface]

  /// Hands the stored pointer handlers to every panel in the pool.
  /// Late mirrors start without them, so this runs on every set and
  /// the sync below repeats it for mirrors made later.
  private func fanOutPointerHandlers() {
    for index in panels.indices {
      panels[index].onHoverRow = onHoverRow
      panels[index].onClickRow = onClickRow
      panels[index].onScrollStep = onScrollStep
    }
  }

  /// Points keys at the cursor display's panel, clamped to the pool.
  /// A single-panel choice always keys the primary panel.
  private func refreshKeyPanel() {
    guard displayTarget == .all else {
      keyPanelIndex = panels.startIndex
      return
    }
    let resolved = keyResolver.resolve(.cursor)
    if case .single(let index) = resolved, panels.indices.contains(index) {
      keyPanelIndex = index
      return
    }
    keyPanelIndex = panels.startIndex
  }

  /// Hands each panel its display before an appearance. Under the
  /// every-display choice the panel at each pool position takes the
  /// display at the same position, so it sizes for and centres on that
  /// display through its own content swaps; otherwise every panel
  /// resolves its display from its own rule.
  private func assignScreens() {
    for (index, surface) in panels.enumerated() {
      (surface as? SwitcherPanel)?.assignedScreenIndex = displayTarget == .all ? index : nil
    }
  }

  /// Puts displayed panels back after the displays have been
  /// rearranged. A panel that is down needs nothing: the next
  /// appearance places it. Outside the every-display choice the
  /// primary panel follows the change itself.
  private func screensChanged() {
    guard isPresented else { return }
    refreshPool()
    refreshKeyPanel()
    guard displayTarget == .all else { return }
    for (index, surface) in panels.enumerated() where surface.isPresented {
      (surface as? SwitcherPanel)?.place(onScreen: index)
    }
  }

}
