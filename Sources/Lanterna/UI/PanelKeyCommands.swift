import AppKit

/// What a key press does to a panel that is up.
///
/// Split from the presenter, which decides when a panel goes up. What becomes
/// of a press once one is there is a different question, and it is the one
/// that grows: every key that reaches the panel through the key channel lands
/// here, and the ones still to be given a meaning land here too.
///
/// Tab and Shift+Tab are the exception, and naming it is what keeps the rule
/// that refuses them from reading as redundant. They move the selection as
/// well, but they arrive through the combination the system was asked to hand
/// over, and the presenter answers them — so the table this reaches through
/// turns a Tab away unconditionally, and a press that came both ways would
/// otherwise move the choice twice. The presenter's file has
/// twice been divided by the length the linter allows, and this is the piece
/// whose next addition is already written down.
///
/// Holds only one appearance's input state — the gathered digits and the
/// remembered repeat — while the panel, the chosen row and the ways out
/// all belong to something else.
@MainActor
final class PanelKeyCommands {

  // MARK: Lifecycle

  init(
    surface: any SwitcherSurface,
    selection: PanelSelection,
    wayOut: PanelExit,
    displayModes: DisplayModes = .defaults,
    exclusionRules: [ExclusionRule] = [],
    searchSettings: SearchSettings = SearchSettings(),
    keyBindings: KeyBindingTable = .defaults,
    now: @escaping @MainActor () -> ContinuousClock.Instant,
    operate: (@Sendable @MainActor (WindowOperation, WindowItem.Identifier?) -> Void)? = nil,
    startFiltering: (@MainActor () -> Void)? = nil,
    openSettings: (@MainActor () -> Void)? = nil
  ) {
    self.surface = surface
    self.selection = selection
    self.wayOut = wayOut
    self.keyBindings = keyBindings
    filter = PanelFilter(selection: selection, surface: surface)
    filter.displayModes = displayModes
    filter.exclusionRules = exclusionRules
    filter.searchSettings = searchSettings
    self.now = now
    self.operate = operate
    self.startFiltering = startFiltering
    self.openSettings = openSettings
  }

  // MARK: Internal

  /// The resolved key bindings this panel goes by. Replaced wholesale
  /// when settings change, the way the exclusion rules are.
  private(set) var keyBindings: KeyBindingTable

  /// Which application is in front as a panel opens. The panel never
  /// activates this process, so the answer is the application the user
  /// was in. Injected so tests name it without a window server.
  var frontmostProcessIdentifier: @MainActor () -> pid_t? = {
    NSWorkspace.shared.frontmostApplication?.processIdentifier
  }

  /// Where a rearranged row order goes. Set by the presenter; the save
  /// reaches the file through it.
  var onRowOrderChanged: (@Sendable @MainActor (ManualRowOrder) -> Void)?

  /// The rows on screen, which the choice and the panel open on.
  var shownWindows: [WindowItem] {
    filter.shownWindows
  }

  /// The same rows as laid out, with their ranked order beside the
  /// drawing order.
  var shownLayout: PanelLayout {
    filter.shownLayout
  }

  /// Whether filtering answers keystrokes right now. The presenter asks
  /// before sending keystrokes here and before treating a released
  /// Command as anything.
  var isFilteringActive: Bool {
    filter.isActive
  }

  /// Starts an appearance over the whole ordered list, filtering only
  /// when the appearance asked for it, on the configured scope. The band
  /// is handed over before the panel goes up, so the panel sizes for it.
  func beginFiltering(fullWindows: [WindowItem], filtering: Bool = false) {
    filter.scopeToggleKey = keyBindings[.toggleScope].first?.displayName
    numberInput.reset()
    repeatSwallow.reset()
    filter.begin(fullWindows: fullWindows, filtering: filtering, activeApplication: frontmostProcessIdentifier())
    surface.showScope(filter.scopeBand)
  }

  /// Hands a changed scope setting to the live filter. The panel that is
  /// up keeps its own until it closes.
  func updateWindowScope(_ scope: WindowScope) {
    filter.scope.configured = scope
  }

  /// Hands a changed grouping to the live filter, so the next list it
  /// lays out groups the new way.
  func updateGrouping(_ grouping: GroupingPolicy) {
    filter.grouping = grouping
  }

  /// Hands changed rules to the live filter, so a settings change
  /// reaches the rows without waiting for the next launch.
  func updateExclusions(_ rules: [ExclusionRule]) {
    filter.exclusionRules = rules
  }

  /// Hands changed search settings to the live filter, the same way.
  func updateSearchSettings(_ settings: SearchSettings) {
    filter.searchSettings = settings
  }

  /// Hands changed bindings to the live panel, so a settings change
  /// reaches the keys without waiting for the next launch.
  func updateKeyBindings(_ bindings: KeyBindingTable) {
    keyBindings = bindings
  }

  /// Hands the number jump switch to the live panel, so a settings
  /// change reaches the keys without waiting for the next launch.
  func updateNumberJump(_ enabled: Bool) {
    numberJumpEnabled = enabled
  }

  /// Hands the reorder switch to the live panel, the same way.
  func updateReorder(_ enabled: Bool) {
    reorderEnabled = enabled
  }

  /// Hands the numbering scope to the live panel, the same way.
  func updateNumberScope(_ scope: NumberScope) {
    numberScope = scope
    filter.numberScope = scope
  }

  /// Hands a changed row order to the live panel, the same way.
  func updateRowOrder(_ order: ManualRowOrder) {
    rowOrder = order
    filter.rowOrder = order
  }

  /// Forgets gathered digits without ending the appearance. A release
  /// that commits nothing still ends the number being typed.
  func resetNumberInput() {
    numberInput.reset()
  }

  /// The rows numbers name, in order: the drawn rows narrowed to the
  /// numbering scope. The same order the choice steps through, so a
  /// number and the selection can never disagree about which row is
  /// which.
  func numberedRows() -> [WindowItem] {
    switch numberScope {
    case .windows:
      shownLayout.rows.filter { $0.id.windowID != nil }
    case .allRows:
      shownLayout.rows
    }
  }

  /// Gives the appearance up; the next one starts empty either way.
  func endFiltering() {
    filter.reset()
    numberInput.reset()
    repeatSwallow.reset()
  }

  /// Swaps the rows on screen for a list an operation hands over — its
  /// optimistic look, the reconciled list, or the look wound back —
  /// keeping the query and the commit's view of the appearance on the
  /// same rows, and moves the choice to where the anchor stood among the
  /// shown rows.
  func replacePresentedList(_ windows: [WindowItem], choosingWhere anchor: ChoiceAnchor) {
    filter.replace(fullWindows: windows, choosingWhere: anchor)
    numberInput.reset()
    wayOut.replacePresented(windows)
  }

  /// Switches filtering on for the panel that is up.
  func activateFiltering() {
    filter.activate()
  }

  /// What the commit and cancel lines will say about this appearance.
  func filterSummary() -> FilterLogSummary {
    filter.logSummary()
  }

  /// Decides what becomes of a key press.
  ///
  /// With no panel up the press is nothing to do with this app, and it goes
  /// on to whatever would have had it. This is the only place that question
  /// is asked: the channel delivering the press keeps no idea of whether a
  /// panel is up, because two records of that are two things that can
  /// disagree.
  ///
  /// With a panel up, everything is swallowed — the keys that mean
  /// something here and equally the ones that mean nothing. The middle
  /// course of handing back only the keys with no meaning was considered
  /// and is wrong twice over. An event handed back travels the responder
  /// chain, and the SDK says plainly what waits at the end of it: a key
  /// press nothing handles rings the system alert. And a character key
  /// passed on would type into whatever is in front, so a panel that is up
  /// would be filling somebody's document while it stood there.
  ///
  /// What the press meant does not change that answer. It decides what
  /// happens here, and every case leaves by the same door.
  ///
  /// The cases with nothing under them are written out rather than swept up
  /// by a `default`, so that the step which gives one of them a body is
  /// made to come here and find it.
  func handle(_ keystroke: PanelKeystroke) -> PanelKeyDisposition {
    // Read before the key is even given a meaning, because giving it one
    // is work done in answer to the press and the span is meant to cover
    // everything this process does about it. A span begun after the
    // mapping would quietly shrink as anything further moved ahead of the
    // read while the figure went on reading the same — the reason the
    // press that puts a panel up is charged its clock read first too.
    //
    // Above the guard costs a read on presses that go no further and buys
    // nothing, since those write no line. It sits there to be one
    // statement away from the entry rather than one condition inside it,
    // the way the press that puts a panel up reads its clock before
    // asking anything.
    let startedAt = now()
    guard surface.isPresented else { return .passedThrough }
    if repeatSwallow.swallows(keystroke) {
      return .absorbed
    }
    // A new press answers the old failure: the note goes before
    // anything the press means is done.
    surface.clearNotice()
    let resolved = PanelKeyInput.action(
      for: keystroke,
      table: keyBindings,
      numberJumpEnabled: numberJumpEnabled,
      reorderEnabled: reorderEnabled,
      filtering: filter.isActive
    )
    // Only consecutive digit presses gather into a number: anything
    // else hands the pending digits back before it is answered.
    if resolved != .numberDigit {
      numberInput.reset()
    }
    switch resolved {
    case .selectNext:
      selection.moveToNext()

    case .selectPrevious:
      selection.moveToPrevious()

    case .cancel:
      cancelOrClear(keystroke, since: startedAt)

    case .commit:
      // Read before the commit: taking the panel down throws the
      // list away. Recorded after the commit returns, so the write
      // lands outside the measured close interval.
      let committedID = selection.chosenID
      let committedQuery = filter.logSummary().query
      wayOut.commit(
        by: PanelKeyInput.commitKey(for: keystroke),
        naming: committedID,
        since: startedAt,
        filter: filter.logSummary()
      )
      recordShortcut(query: committedQuery, id: committedID)

    case .clearQuery:
      // Clearing an empty query changes nothing, and the panel
      // stays up either way: there is nothing to cancel here.
      _ = filter.clear()

    case .windowOperation(let operation):
      operate?(operation, selection.chosenID)

    case .toggleScope:
      filter.toggleScope()

    case .startFiltering:
      guard !filter.isActive else { break }
      repeatSwallow.hold(keystroke.keyCode)
      startFiltering?()

    case .openSettings:
      let summary = filter.logSummary()
      wayOut.leaveForSettings(
        by: PanelKeyInput.settingsKey(for: keystroke),
        since: startedAt,
        filter: summary
      )
      openSettings?()

    case .filterText(let text):
      filter.append(text)

    case .filterBackspace:
      filter.removeLast()

    case .numberDigit:
      guard numberJumpEnabled, let digit = PanelKeyInput.digitValue(for: keystroke.keyCode) else {
        break
      }
      numberInput.append(digit)
      guard let number = numberInput.number else { break }
      let rows = numberedRows()
      guard rows.indices.contains(number - 1) else { break }
      selection.select(rows[number - 1].id)

    case .moveRowUp:
      moveSelectedRow(by: -1)

    case .moveRowDown:
      moveSelectedRow(by: 1)

    case .absorb:
      break
    }
    return .absorbed
  }

  /// Commits the clicked row the way a commit key would: the row is
  /// chosen first, then the same way out and the same shortcut record
  /// run. The span starts at the click, so the measured close covers
  /// what this process does about the click and nothing before it.
  func commitClickedRow(_ id: WindowItem.Identifier?) {
    guard surface.isPresented else { return }
    if let id, !filter.shownWindows.contains(where: { $0.id == id }) {
      return
    }
    let startedAt = now()
    // Read before the commit: taking the panel down throws the
    // list away. Recorded after the commit returns, so the write
    // lands outside the measured close interval.
    if let id {
      selection.select(id)
    }
    let committedID = selection.chosenID
    let summary = filter.logSummary()
    wayOut.commit(
      by: .click,
      naming: committedID,
      since: startedAt,
      filter: summary
    )
    recordShortcut(query: summary.query, id: committedID)
  }

  // MARK: Private

  /// Whether digits with a jump modifier name rows. Off reads as the
  /// table holding no number row.
  private var numberJumpEnabled = false
  /// Whether reorder presses move rows. Off reads as the table
  /// holding neither reorder row.
  private var reorderEnabled = false
  /// Which rows numbers name. Window rows alone unless told otherwise.
  private var numberScope = NumberScope.windows
  /// The hand-arranged row orders shadowing the drawn order.
  private var rowOrder = ManualRowOrder.none
  /// The digits gathered since the last reset.
  private var numberInput = NumberInput()
  /// The key code whose repeats read as nothing after switching.
  private var repeatSwallow = KeyRepeatSwallow()

  private let surface: any SwitcherSurface
  private let selection: PanelSelection
  private let wayOut: PanelExit
  private let filter: PanelFilter
  private let now: @MainActor () -> ContinuousClock.Instant
  /// Handed the row chosen as the key is pressed, so a choice moved
  /// before the operation gets its turn does not change its target.
  private let operate: (@Sendable @MainActor (WindowOperation, WindowItem.Identifier?) -> Void)?
  /// Switches the presented panel into filtering, through the presenter.
  private let startFiltering: (@MainActor () -> Void)?
  /// Opens the settings, through the presenter.
  private let openSettings: (@MainActor () -> Void)?

  /// Moves the chosen row one step inside its manual group, saving the
  /// rearranged order through the handler above. Anything outside a
  /// manual group, under a query, at an edge, or past a boundary is
  /// left alone: the press then means nothing, the way an absorbed
  /// press does.
  private func moveSelectedRow(by delta: Int) {
    guard
      reorderEnabled,
      filter.grouping.mode == .manual,
      !filter.isFiltering,
      let selected = selection.chosenID
    else {
      return
    }
    var groupNumbers = [Int]()
    var segments = [[WindowItem]]()
    for block in shownLayout.blocks {
      switch block {
      case .groupHeading(_, let order):
        groupNumbers.append(order)
        segments.append([])

      case .subgroupHeading:
        break

      case .row(let window, _):
        guard !segments.isEmpty else { return }
        segments[segments.count - 1].append(window)
      }
    }
    guard
      let segmentIndex = segments.firstIndex(where: { segment in
        segment.contains(where: { $0.id == selected })
      }),
      let rowIndex = segments[segmentIndex].firstIndex(where: { $0.id == selected })
    else {
      return
    }
    let target = rowIndex + delta
    guard segments[segmentIndex].indices.contains(target) else { return }
    var arranged = segments[segmentIndex]
    arranged.swapAt(rowIndex, target)
    let updated = rowOrder.setting(group: groupNumbers[segmentIndex], arranging: arranged)
    updateRowOrder(updated)
    filter.applyRowOrder(updated)
    onRowOrderChanged?(updated)
  }

  /// Decides a cancel press: a clear key clears the query first and
  /// only cancels on an empty one. The table cannot tell the two
  /// apart: it keeps no state, and the filter is where the question
  /// is answered.
  private func cancelOrClear(_ keystroke: PanelKeystroke, since startedAt: ContinuousClock.Instant) {
    if keyBindings.matches(keystroke, action: .clearQuery, filtering: filter.isActive), filter.clear() {
      return
    }
    wayOut.cancel(
      by: PanelKeyInput.cancelKey(for: keystroke),
      since: startedAt,
      filter: filter.logSummary()
    )
  }

  /// Records one commit for shortcut memory. Empty queries, overlong
  /// queries, and a zero cap record nothing, as does no row at all.
  private func recordShortcut(query: String, id: WindowItem.Identifier?) {
    guard let id else { return }
    filter.recordShortcut(query: query, id: id)
  }

}
