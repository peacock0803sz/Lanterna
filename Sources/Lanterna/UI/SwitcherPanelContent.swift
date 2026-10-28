import AppKit
import SwiftUI

/// The hosted-list swaps of the switcher panel, split out when the panel
/// file reached the file-length limit. State stays in `SwitcherPanel`;
/// everything that swaps the list or grows the frame for a note lives
/// here.
extension SwitcherPanel {
  /// The content size for a list under this appearance: its text step,
  /// width step, row limit, and the display it sits on. Every swap and
  /// the scope band take their size from here, so they cannot disagree.
  func contentSize(
    windows: [WindowItem],
    query: String,
    filterActive: Bool,
    notice: Bool
  ) -> CGSize {
    PanelMetrics.panelSize(
      rowCount: PanelMetrics.drawnRowCount(
        windows,
        modes: displayModes,
        query: query,
        exclusions: exclusionRules,
        fuzzy: searchSettings.fuzzyMatchEnabled,
        grouping: grouping
      ),
      query: query,
      filterActive: filterActive,
      notice: notice,
      scopeBand: scopeBand != nil,
      for: appearanceScale,
      step: appearanceWidth,
      rows: appearanceRows,
      visibleHeight: visibleHeight
    )
  }

  /// One swap of the hosted list, carrying the choice, the query, the
  /// insertion point, and the chrome across. Both `update` paths funnel through here so the
  /// view the panel sizes is the view it draws.
  func swappedView(
    windows: [WindowItem],
    selectedID: WindowItem.Identifier?,
    appearanceToken: Int,
    query: String,
    cursor: Int,
    filterActive: Bool
  ) -> SwitcherView {
    SwitcherView(
      windows: windows,
      selectedID: selectedID,
      appearanceToken: appearanceToken,
      query: query,
      cursor: cursor,
      filterActive: filterActive,
      modes: displayModes,
      exclusionRules: exclusionRules,
      fuzzyMatchEnabled: searchSettings.fuzzyMatchEnabled,
      textScale: appearanceScale,
      scopeBand: scopeBand,
      grouping: grouping,
      hoverSelect: hoverSelect,
      scrollSelect: scrollSelect,
      hoverAnchor: hoverAnchor,
      numberedIDs: numberedIDs,
      hintsMode: appearanceHints,
      badges: badges,
      onHoverRow: onHoverRow,
      onClickRow: onClickRow
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
    let size = contentSize(
      windows: view.windows,
      query: view.query,
      filterActive: view.filterActive,
      notice: notice != nil
    )
    resizeKeepingTop(to: size.height)
  }

  /// Sizes the content to this appearance on the remembered screen from
  /// the list on show, and centres there. A display change calls this
  /// rather than reusing the frame on hand, whose height was cut to the
  /// display it came from.
  func refitToResolvedScreen() {
    let view = hostingView.rootView
    let size = contentSize(
      windows: view.windows,
      query: view.query,
      filterActive: view.filterActive,
      notice: false
    )
    if notice != nil {
      noticeGrowth = PanelMetrics.noticeGrowth(from: size.height, in: visibleHeight, for: appearanceScale)
    }
    setContentSize(NSSize(width: fittedWidth(size.width), height: size.height + noticeGrowth))
    stayOnResolvedScreen()
  }

  /// Changes the height with the top edge staying where it was, unless
  /// that would push the panel off the remembered screen. A short panel
  /// sits centred, so growing it to a long row limit from there would.
  func resizeKeepingTop(to height: CGFloat) {
    var frame = frame
    frame.origin.y -= height - frame.height
    frame.size.height = height
    if let visible = resolvedVisibleFrame {
      frame = PanelMetrics.keptOnScreen(frame, in: visible)
    }
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
      cursor: hostingView.rootView.cursor,
      filterActive: hostingView.rootView.filterActive
    )
    // The height is pushed down from the window, because the hosting view
    // has no sizing options and so cannot push one up.
    let size = contentSize(
      windows: windows,
      query: hostingView.rootView.query,
      filterActive: hostingView.rootView.filterActive,
      notice: false
    )
    setContentSize(NSSize(width: fittedWidth(size.width), height: size.height))
    stayOnResolvedScreen()
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
    cursor: Int,
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
      cursor: cursor,
      filterActive: filterActive
    )
    let size = contentSize(windows: windows, query: query, filterActive: filterActive, notice: false)
    resizeKeepingTop(to: size.height)
  }

  /// Redraws only the query row's insertion point, the way
  /// `showSelection` redraws only the choice.
  func showCursor(_ position: Int) {
    hostingView.rootView.cursor = position
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
    // The growth stops at the display's room, so a full panel stays on screen.
    let grown = PanelMetrics.noticeGrowth(from: frame.height, in: visibleHeight, for: appearanceScale)
    noticeGrowth = grown
    resizeKeepingTop(to: frame.height + grown)
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
