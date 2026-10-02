import AppKit
import SwiftUI

/// The hosted-list swaps of the switcher panel, split out when the panel
/// file reached the file-length limit. State stays in `SwitcherPanel`;
/// everything that swaps the list or grows the frame for a note lives
/// here.
extension SwitcherPanel {
  /// One swap of the hosted list, carrying the choice, the query, and
  /// the chrome across. Both `update` paths funnel through here so the
  /// view the panel sizes is the view it draws.
  func swappedView(
    windows: [WindowItem],
    selectedID: WindowItem.Identifier?,
    appearanceToken: Int,
    query: String,
    filterActive: Bool
  ) -> SwitcherView {
    SwitcherView(
      windows: windows,
      selectedID: selectedID,
      appearanceToken: appearanceToken,
      query: query,
      filterActive: filterActive,
      modes: displayModes,
      exclusionRules: exclusionRules,
      fuzzyMatchEnabled: searchSettings.fuzzyMatchEnabled,
      textScale: appearanceScale,
      scopeBand: scopeBand
    )
  }

  /// Shows the band over a list narrowed to one application, or takes it
  /// down, resizing to the list with the top edge staying where it was.
  /// Asked before an appearance goes up too, so the first frame is sized
  /// for the band.
  func showScope(_ band: ScopeBand?) {
    guard band != scopeBand else { return }
    scopeBand = band
    hostingView.rootView.scopeBand = band
    let view = hostingView.rootView
    let size = PanelMetrics.panelSize(
      rowCount: PanelMetrics.drawnRowCount(
        view.windows,
        modes: displayModes,
        query: view.query,
        exclusions: exclusionRules,
        fuzzy: searchSettings.fuzzyMatchEnabled
      ),
      query: view.query,
      filterActive: view.filterActive,
      notice: notice != nil,
      scopeBand: band != nil,
      for: appearanceScale
    )
    var frame = frame
    frame.origin.y -= size.height - frame.height
    frame.size.height = size.height
    setFrame(frame, display: true)
  }

  /// Replaces the list and resizes to it, leaving the panel where it was:
  /// off screen if it was off screen, on screen if it was on.
  ///
  /// `SwitcherView` holds nothing but its array and the package has no
  /// observable state anywhere, so assigning a new root view is a complete
  /// swap; SwiftUI diffs the rows by their identity from there.
  ///
  /// Carries the chosen row across the swap. Assigning a new root view
  /// replaces every field of it, so a list arriving without the selection
  /// beside it would leave the panel drawing no row as chosen while the
  /// presenter went on believing one was — the sort of failure that shows
  /// on screen and nowhere else.
  func update(windows: [WindowItem]) {
    // Both are dropped here because the size below counts no note.
    notice = nil
    noticeGrowth = 0
    hostingView.rootView = swappedView(
      windows: windows,
      selectedID: hostingView.rootView.selectedID,
      appearanceToken: hostingView.rootView.appearanceToken,
      query: hostingView.rootView.query,
      filterActive: hostingView.rootView.filterActive
    )
    // The height is pushed down from the window, because the hosting view
    // has no sizing options and so cannot push one up.
    let query = hostingView.rootView.query
    let filterActive = hostingView.rootView.filterActive
    let size = PanelMetrics.panelSize(
      rowCount: PanelMetrics.drawnRowCount(
        windows,
        modes: displayModes,
        query: query,
        exclusions: exclusionRules,
        fuzzy: searchSettings.fuzzyMatchEnabled
      ),
      query: query,
      filterActive: filterActive,
      notice: false,
      scopeBand: scopeBand != nil,
      for: appearanceScale
    )
    setContentSize(NSSize(width: size.width, height: size.height))
    centerOnMainDisplay()
  }

  /// Swaps the rows for a narrowed set, and changes nothing else about
  /// the panel's place.
  ///
  /// A new root view like `update(windows:)` swaps, but without the centre
  /// that call decides: narrowing happens a keystroke at a time, and a
  /// panel that jumped on every one would be one the eye has to find
  /// again. Only the height follows the content, with the top edge staying
  /// where it was, so the first rows keep their place while the list
  /// narrows. The appearance token travels across untouched, so the
  /// scrolled position is left where it was.
  func updateList(
    windows: [WindowItem],
    selecting: WindowItem.Identifier?,
    query: String,
    filterActive: Bool
  ) {
    // Both are dropped here because the size below counts no note.
    notice = nil
    noticeGrowth = 0
    hostingView.rootView = swappedView(
      windows: windows,
      selectedID: selecting,
      appearanceToken: hostingView.rootView.appearanceToken,
      query: query,
      filterActive: filterActive
    )
    let size = PanelMetrics.panelSize(
      rowCount: PanelMetrics.drawnRowCount(
        windows,
        modes: displayModes,
        query: query,
        exclusions: exclusionRules,
        fuzzy: searchSettings.fuzzyMatchEnabled
      ),
      query: query,
      filterActive: filterActive,
      notice: false,
      scopeBand: scopeBand != nil,
      for: appearanceScale
    )
    var frame = frame
    frame.origin.y -= size.height - frame.height
    frame.size.height = size.height
    setFrame(frame, display: true)
  }

  /// Shows a small failure note under the list, growing the panel for it
  /// with the top edge staying where it was.
  func showNotice(_ text: String) {
    guard notice == nil else {
      hostingView.rootView.notice = text
      return
    }
    notice = text
    hostingView.rootView.notice = text
    var frame = frame
    // The growth stops at the height limit, so a full panel stays on screen.
    let grown = min(
      PanelMetrics.noticeHeight(for: appearanceScale),
      max(PanelMetrics.maximumHeight - frame.height, 0)
    )
    noticeGrowth = grown
    frame.origin.y -= grown
    frame.size.height += grown
    setFrame(frame, display: true)
  }

  /// Takes the failure note down, giving its height back.
  func clearNotice() {
    guard notice != nil else {
      return
    }
    notice = nil
    hostingView.rootView.notice = nil
    var frame = frame
    // Gives back what showing took, rather than recomputing it.
    let grown = noticeGrowth
    noticeGrowth = 0
    frame.origin.y += grown
    frame.size.height -= grown
    setFrame(frame, display: true)
  }
}
