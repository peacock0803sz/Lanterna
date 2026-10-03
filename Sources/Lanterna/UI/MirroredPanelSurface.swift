import AppKit
import Foundation

// MARK: - MirroredPanelSurface

/// Shows one appearance on every panel at once, with the same rows,
/// choice and query everywhere.
///
/// Only the cursor display's panel takes keys; the rest mirror what
/// it shows. The pool behind the panels is sized elsewhere and handed
/// in, so this type never creates a window: appearing on an unchanged
/// pool costs nothing it did not already cost.
@MainActor
final class MirroredPanelSurface: SwitcherSurface {

  // MARK: Lifecycle

  init(
    panels: [any SwitcherSurface],
    keyResolver: DisplayResolver = DisplayResolver(),
    place: (@MainActor ([any SwitcherSurface]) -> Void)? = nil,
    ensurePool: (@MainActor () -> [any SwitcherSurface])? = nil
  ) {
    precondition(!panels.isEmpty, "mirroring needs at least one panel")
    self.panels = panels
    self.keyResolver = keyResolver
    self.place = place
    self.ensurePool = ensurePool
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
    place?(panels)
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

  // MARK: Private

  private var panels: [any SwitcherSurface]
  private let place: (@MainActor ([any SwitcherSurface]) -> Void)?
  private let ensurePool: (@MainActor () -> [any SwitcherSurface])?

  /// Brings the pool to the connected displays. Without a pool keeper
  /// the opening pool stands, which is the single-display case.
  private func refreshPool() {
    guard let grown = ensurePool?(), !grown.isEmpty else {
      return
    }
    panels = grown
    keyPanelIndex = min(keyPanelIndex, panels.count - 1)
  }

  /// Points keys at the cursor display's panel, clamped to the pool.
  private func refreshKeyPanel() {
    let resolved = keyResolver.resolve(.cursor)
    if case .single(let index) = resolved, panels.indices.contains(index) {
      keyPanelIndex = index
      return
    }
    keyPanelIndex = panels.startIndex
  }

  /// Puts displayed panels back after the displays have been
  /// rearranged. A panel that is down needs nothing: the next
  /// appearance places it.
  private func screensChanged() {
    guard isPresented else { return }
    refreshPool()
    refreshKeyPanel()
    place?(panels)
  }

}
