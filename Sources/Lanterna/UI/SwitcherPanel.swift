import AppKit
import SwiftUI

/// Borderless floating panel that hosts the switcher list.
///
/// The non-activating style is what lets the panel appear without taking focus
/// away from the application the user is working in.
///
/// One panel is built once and shown many times. Rebuilding it per appearance
/// would put window creation on the path between the key press and the panel,
/// which is the one path that has a time budget.
final class SwitcherPanel: NSPanel {

  // MARK: Lifecycle

  /// The window decides its own size and the hosting view is denied any say
  /// in it. `update(windows:)` decides it again for a swapped-in list; the
  /// two cannot disagree, because both take their numbers from
  /// `PanelMetrics`. The initial content is the empty, unfiltered list.
  init(
    content: SwitcherView = SwitcherView(
      windows: [],
      selectedID: nil,
      appearanceToken: 0,
      query: "",
      filterActive: false
    ),
    displayModes: DisplayModes = .defaults,
    exclusionRules: [ExclusionRule] = [],
    appearanceMode: AppearanceMode = .system,
    searchSettings: SearchSettings = SearchSettings(),
    textScale: TextScaleLevel = .standard
  ) {
    self.displayModes = displayModes
    self.exclusionRules = exclusionRules
    self.searchSettings = searchSettings
    self.textScale = textScale
    appearanceScale = textScale
    hostingView = NSHostingView(rootView: content)
    let initial = PanelMetrics.panelSize(
      rowCount: PanelMetrics.drawnRowCount(
        content.windows,
        modes: displayModes,
        query: content.query,
        exclusions: exclusionRules,
        fuzzy: searchSettings.fuzzyMatchEnabled
      ),
      query: content.query,
      filterActive: content.filterActive,
      notice: false,
      for: textScale
    )
    super.init(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: initial.width,
        height: initial.height
      ),
      // Borderless is the absence of `.titled`, so it needs no flag.
      styleMask: [.nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    // Liquid Glass brings its own shadow, so the window must not draw the
    // one NSPanel gives it by default. Drawing the shadow inside SwiftUI
    // instead is not an option: it would be clipped, because the panel
    // frame is exactly the content frame.
    hasShadow = false
    hidesOnDeactivate = false
    // The light or dark look is set on the window, not on the root view,
    // so swapping in a new root view cannot drop it.
    appearance = appearanceMode.nsAppearance

    // With no sizing options the SwiftUI intrinsic size cannot change the
    // window's content size or its minimum and maximum sizes.
    hostingView.sizingOptions = []
    contentView = hostingView

    // Nothing is removed. The observation ends with the process, and the
    // notification centre holds the token in the meantime whether or not
    // anyone else does.
    _ = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // The queue above is the main one, so this is the main actor's
      // executor; nothing weaker than a trap is wanted if that ever
      // stops being true.
      MainActor.assumeIsolated {
        self?.screensChanged()
      }
    }
  }

  // MARK: Internal

  /// Held rather than dropped at the end of `init`: swapping the list in
  /// place needs a handle on the view that holds it.
  let hostingView: NSHostingView<SwitcherView>

  /// How the special kinds show, read at launch from the config file.
  /// Kept here so the height counts what the view draws.
  var displayModes = DisplayModes.defaults

  /// The compiled exclusion rules. Kept beside the modes for the same
  /// reason: the height counts what the view draws, exclusions first.
  var exclusionRules = [ExclusionRule]()

  /// The three search-quality settings as one value. Kept beside the
  /// modes: the height counts what the view draws.
  var searchSettings = SearchSettings()

  /// The text and icon scale step, read at launch from the config file.
  /// A change takes effect on the next appearance, never on the one
  /// already up: resizing under an open panel would move the choice
  /// the eye is following.
  var textScale = TextScaleLevel.standard

  /// The step the appearance on screen opened with. Frozen at `present`
  /// so narrowing or a notice mid-appearance cannot resize what is up.
  var appearanceScale = TextScaleLevel.standard

  /// The failure note on screen now, if any. Remembered here so the panel
  /// knows whether the note's height is in its frame, and clearing gives
  /// back exactly what showing took. A swapped list sizes the frame
  /// without it, and a new appearance starts without one.
  var notice: String?

  /// How much the frame grew for the note on screen now. Kept beside
  /// the note so clearing gives back exactly what showing took, even
  /// when showing was capped to stay within the height limit.
  var noticeGrowth: CGFloat = 0

  /// The band over a list narrowed to one application, if one shows.
  /// Kept here so every swap of the list draws it and sizes for it.
  var scopeBand: ScopeBand?

  /// How the rows are grouped. A change lands with the next swap of the
  /// list, like the modes.
  var grouping = GroupingPolicy()

  /// Whether the panel is currently on screen.
  var isPresented: Bool {
    isVisible
  }

  /// Whether key presses are reaching this panel at this instant.
  var isTakingKeys: Bool {
    isKeyWindow
  }

  /// Which row the panel is drawing as chosen at this instant.
  ///
  /// The way in to a promise that is otherwise out of reach. Both the swap
  /// in `update(windows:)` and the write in `present(windows:selecting:)`
  /// land inside the hosting view, and what a hosting view draws shows on a
  /// screen and nowhere else: a swap that dropped the choice, or an
  /// appearance that kept the last one, would leave the panel highlighting
  /// a row nobody chose while every caller went on believing otherwise.
  ///
  /// Read back off the view rather than remembered beside it, for the
  /// reason `isPresented` is read off the window: two records of one thing
  /// are two things that can disagree, and the one that disagrees silently
  /// here is the one the user is looking at.
  var shownSelection: WindowItem.Identifier? {
    hostingView.rootView.selectedID
  }

  /// The panel is allowed to take key status, and the process must never
  /// become the active application. Those are two different things, and
  /// this is the line between them: key presses can come here, while the
  /// application the user is working in stays the active one, keeps its
  /// menu bar and keeps its main window.
  ///
  /// What is settled here is the permission, not the asking. A window that
  /// answers no has its key requests dropped without a word, so this is
  /// what `takeKeys()` rests on — and whether anything calls that is
  /// decided elsewhere.
  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }

  /// Ordered front regardless rather than made key and ordered front.
  /// Apple says of the ordinary order-front that a window cannot be moved
  /// in front of the key window unless the two belong to the same
  /// application, and that proviso describes this panel's situation
  /// exactly: it floats above whatever the user is working in.
  ///
  /// The chosen row is written after the list is swapped in, and never
  /// left out. The swap carries over whichever row was chosen last time,
  /// so a panel put up a second time without this would keep the old
  /// highlight while the code that moves the selection believed it was back
  /// on the first row. `shownSelection` reads the drawn choice back off the
  /// view, which is what lets the tests of this class put a real panel up
  /// twice and hold the second appearance to the row it was given.
  ///
  /// The query and the chrome are set before the swap for the same
  /// reason: the swap carries them over too, and a query left from the
  /// last appearance would keep narrowing the rows drawn while the
  /// choice steps through all of them. Every appearance opens on an
  /// empty query, with the chrome on only when it opened filtering.
  func present(windows: [WindowItem], selecting: WindowItem.Identifier?, filterActive: Bool = false) {
    appearances += 1
    notice = nil
    noticeGrowth = 0
    appearanceScale = textScale
    hostingView.rootView.query = ""
    hostingView.rootView.filterActive = filterActive
    update(windows: windows)
    hostingView.rootView.appearanceToken = appearances
    showSelection(selecting)
    orderFrontRegardless()
  }

  /// Asks the window server to send key presses here, and answers whether
  /// it did.
  ///
  /// Kept out of `present` on purpose. The tests of this class put a real
  /// panel up twice, and taking the keyboard inside `present` would mean
  /// every run of the suite pulled the developer's typing into a panel that
  /// nothing on screen has shown them. A separate entry those tests do not
  /// call makes that a matter of structure rather than of remembering; an
  /// argument controlling it would only move the remembering to the call.
  ///
  /// The answer is read back from the window rather than assumed from the
  /// asking. A window that cannot become key drops the request silently,
  /// and so does one asked while the application is in a state that does
  /// not allow it.
  func takeKeys() -> Bool {
    makeKey()
    return isKeyWindow
  }

  /// Redraws with a different row chosen, and changes nothing else.
  ///
  /// One assignment, and deliberately not a trip through `update(windows:)`
  /// — that path resizes the window and puts it back in the centre of the
  /// display, neither of which may happen because somebody pressed an
  /// arrow. A panel that resized or jumped as the selection moved would be
  /// a panel the eye has to find again on every keystroke.
  func showSelection(_ id: WindowItem.Identifier?) {
    hostingView.rootView.selectedID = id
  }

  func dismiss() {
    orderOut(nil)
  }

  /// Puts the panel back where it belongs after the displays have been
  /// rearranged.
  ///
  /// Between appearances nothing moves the panel, so a display change would
  /// otherwise leave one that is up wherever the old arrangement had put it:
  /// off centre on the display that is now the main one, or on a display the
  /// user is no longer looking at. That second case costs a press. Changing
  /// which display is the main one with the panel up was seen to leave a
  /// panel the next press did not appear to take down — the line was
  /// written, and nothing on the display in front of the user changed; the
  /// press after that moved and showed it, and only the third took it down.
  /// What the window server was doing was not established, and a panel the
  /// user simply cannot see would look the same from where the press was
  /// made. Moving it here is what keeps that state from arising either way.
  ///
  /// A panel that is down needs nothing. The next appearance places it, and
  /// this runs whenever anyone plugs in a display.
  func screensChanged() {
    guard isPresented else { return }
    centerOnMainDisplay()
  }

  // `becomesKeyOnlyIfNeeded` is deliberately left alone. Its default is
  // false, and an early sketch of this feature set it to true in the
  // belief that this was what let a panel take keys without activating.
  // It is not: the flag governs only whether clicking a panel makes it
  // key, and has no say over `makeKey()` at all.

  /// `NSWindow.center()` centres on whichever screen the window already sits
  /// on, so the display is picked explicitly. `NSScreen.screens.first` is the
  /// display that carries the menu bar, which is the one the panel belongs
  /// on; `NSScreen.main` would instead follow the key window and so could be
  /// any display.
  ///
  /// Run on every update, because a resize leaves the panel off centre.
  func centerOnMainDisplay() {
    guard let area = NSScreen.screens.first?.visibleFrame else {
      center()
      return
    }
    let size = frame.size
    setFrameOrigin(
      NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
    )
  }

  // MARK: Private

  /// Counts the appearances, so the view can tell one from the next. The
  /// scrolled position survives a reused panel, and without something that
  /// moves every time, an appearance opening on an unchanged choice would
  /// leave `.onChange(of:)` silent and the list where the last one left
  /// it.
  private var appearances = 0

}
