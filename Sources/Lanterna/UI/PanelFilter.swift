import AppKit
import Logging

// MARK: - ChoiceAnchor

/// Where the operated row stood before a list was swapped: the row, and the
/// whole list it stood in. The filter counts the place among the rows it
/// shows.
struct ChoiceAnchor {
  let id: WindowItem.Identifier
  let stoodIn: [WindowItem]
}

// MARK: - PanelFilter

/// What typing does to a panel that is up.
///
/// Split from the commands, which decide what a press means in the large:
/// narrowing, shortening, and clearing a query are one question, and moving,
/// committing, and cancelling are another. Holding the memory itself would
/// join distribution with keeping, so the memory is a value (`FilterState`)
/// and this is its keeper — the one place a keystroke redraws the rows.
///
/// Holds no list of its own. The whole list of the appearance arrives with
/// `begin`, and everything after that is a narrowed view of it.
@MainActor
final class PanelFilter {

  // MARK: Lifecycle

  init(selection: PanelSelection, surface: any SwitcherSurface) {
    self.selection = selection
    self.surface = surface
  }

  // MARK: Internal

  /// The three search-quality settings as one value. Read at launch
  /// from the config file and whenever the settings change, like the
  /// exclusion rules are recompiled.
  var searchSettings = SearchSettings()
  /// Whether keystrokes narrow the list right now. Set only by the filter
  /// invocation; a panel shown any other way leaves it off, and typing is
  /// swallowed as before.
  private(set) var isActive = false
  /// How the special kinds show. Read at launch from the config file;
  /// the panel keeps the rows and this decides which reach the screen.
  var displayModes = DisplayModes.defaults
  /// Where the per-appearance lines go. Wired like the presenter's, so
  /// tests can read what an appearance reports without stderr. Falls
  /// silent while the diagnostics logger is down (tests reading no log),
  /// because the process only wires it on the launch path.
  var writeLine: @MainActor (LogLine) -> Void = { line in
    guard Diagnostics.logger != nil else { return }
    Diagnostics.writeLine(line)
  }

  /// The compiled exclusion rules. Read at launch from the config file
  /// and recompiled whenever the settings change; the panel keeps the
  /// rows and these decide which leave before anything else sees them.
  var exclusionRules = [ExclusionRule]()

  /// Which applications' rows this appearance lists, and whose they are
  /// when narrowed. The configured scope is set from the settings.
  var scope = ScopeState()

  /// How the band names the key that switches the scope back.
  var scopeToggleKey: String?

  /// How the rows are grouped. Read at launch from the config file and
  /// whenever the settings change, like the modes.
  var grouping = GroupingPolicy()

  /// Whether a query is narrowing the list right now.
  var isFiltering: Bool {
    !state.query.isEmpty
  }

  /// The band over a list narrowed to one application, or nil while every
  /// application is listed. Named the way that application's rows name
  /// it, or by the running application when it has no row.
  var scopeBand: ScopeBand? {
    guard let owner = scope.narrowedOwner else { return nil }
    let name = fullWindows.first { $0.ownerProcessIdentifier == owner }?.appName
      ?? NSRunningApplication(processIdentifier: owner)?.localizedName
    return ScopeBand(appName: name ?? "Active app", toggleKey: scopeToggleKey)
  }

  /// The rows on screen: the whole list narrowed by the query and the
  /// display modes, in the order the panel draws them. The whole list
  /// stays underneath, so a query can still bring back a row the modes
  /// keep out.
  var shownWindows: [WindowItem] {
    shown(in: fullWindows)
  }

  /// Starts an appearance over the whole ordered list, remembering nothing.
  /// Filtering answers keystrokes only when the appearance asked for it.
  /// Draws nothing: the caller opens the choice and the panel on
  /// `shownWindows`, so the modes narrow the list before either sees it.
  func begin(fullWindows: [WindowItem], filtering: Bool = false, activeApplication: pid_t? = nil) {
    self.fullWindows = fullWindows
    state = FilterState()
    scope.begin(target: activeApplication)
    let shown = shownWindows
    state.previousMatchedIDs = Set(shown.map(\.id))
    lastSummary = FilterLogSummary(query: "", matchedCount: shown.count, totalCount: fullWindows.count)
    isActive = filtering
    // Without rules there is nothing to report, so stay quiet.
    guard !exclusionRules.isEmpty else { return }
    let excluded = fullWindows.count - WindowExclusion.excluding(fullWindows, rules: exclusionRules).count
    writeLine(LogLine(.info, .filter, "excluded \(excluded) of \(fullWindows.count) windows"))
  }

  /// Switches filtering on for the panel that is up, drawing at once: the
  /// chrome appears with the activation rather than with the next keystroke.
  func activate() {
    guard !isActive else { return }
    isActive = true
    apply()
  }

  /// Swaps the list underneath, keeping the query: the narrowing stays
  /// on over the new rows. The counts the commit and cancel lines print
  /// are recomputed against the new rows. A row a query hid while it
  /// was chosen is not chosen again merely because the new list brings
  /// it back: that happens with shortening, not with a swap.
  func replace(fullWindows: [WindowItem]) {
    self.fullWindows = fullWindows
    state.takeSwappedIn(matched: shownWindows.map(\.id))
    apply()
  }

  /// Swaps the list underneath as above, moving the choice to the row now
  /// standing at the anchor's place among the shown rows, or to the last
  /// shown row when fewer rows are shown than that. Counted among the
  /// shown rows, in the order the panel draws them, and not the whole
  /// list, so a narrowed panel never chooses a row it is not showing. A
  /// row that keeps its place keeps the choice. An operation that moves
  /// the row elsewhere in the drawing, or out of it, leaves the choice at
  /// the place the row left, as it does when a row goes. An anchor
  /// that was not shown, or a list that shows nothing, leaves the choice
  /// to the usual resolving.
  func replace(fullWindows: [WindowItem], choosingWhere anchor: ChoiceAnchor) {
    let before = shown(in: anchor.stoodIn).map(\.id)
    let after = shown(in: fullWindows).map(\.id)
    if let index = before.firstIndex(of: anchor.id), let last = after.indices.last {
      selection.retarget(to: after, selecting: after[min(index, last)])
    }
    replace(fullWindows: fullWindows)
  }

  /// Gives the appearance up; the next one starts empty either way.
  func reset() {
    fullWindows = []
    state = FilterState()
    lastSummary = FilterLogSummary(query: "", matchedCount: 0, totalCount: 0)
    isActive = false
  }

  /// Records one commit under the query it committed with. Movements
  /// of the choice record nothing; only the commit path calls here.
  /// Empty queries, overlong queries, and a zero cap record nothing.
  func recordShortcut(query: String, id: WindowItem.Identifier) {
    shortcutMemory.maxLength = searchSettings.shortcutMemoryLength
    shortcutMemory.record(query: query, id: id)
  }

  /// What the commit and cancel lines will say about this appearance.
  ///
  /// Read at the exits, which write their lines after the closing: the
  /// value travels with the call, so no state outlives the panel it
  /// describes.
  func logSummary() -> FilterLogSummary {
    lastSummary
  }

  /// Switches this appearance between every application's rows and the
  /// active application's alone, keeping the query. The choice stays on
  /// its row when the row is still listed, and goes to the first row
  /// otherwise, the way narrowing moves it.
  func toggleScope() {
    scope.toggle()
    surface.showScope(scopeBand)
    apply()
    let word = scope.current.rawValue
    writeLine(LogLine(.info, .panel, "scope \(word)", context: ["scope": .string(word)]))
  }

  /// Narrows one keystroke further. Answers nothing while inactive.
  func append(_ text: String) {
    guard isActive else { return }
    state.append(text)
    apply()
  }

  /// Shortens the query by one character, and does nothing when already
  /// empty: there is nothing to narrow back to that the panel is not
  /// already showing.
  func removeLast() {
    guard isActive, isFiltering else { return }
    state.removeLast()
    apply()
  }

  /// Clears the query, leaving the panel up over the whole list.
  ///
  /// Answers whether there was a query to clear: an empty query clears
  /// nothing, and the caller treats that press the way it always did.
  /// The answer is not one a caller may drop: clearing and cancelling
  /// are different fates for one press, and forgetting to ask would
  /// silently turn one into the other.
  func clear() -> Bool {
    guard isActive, isFiltering else { return false }
    state.clear()
    apply()
    return true
  }

  // MARK: Private

  private var fullWindows = [WindowItem]()
  private var state = FilterState()
  /// The shortcut memory, kept across appearances while the process
  /// runs. The query starts over with every appearance; the habits do
  /// not.
  private var shortcutMemory = ShortcutMemory(maxLength: 5)

  private var lastSummary = FilterLogSummary(query: "", matchedCount: 0, totalCount: 0)

  private let selection: PanelSelection
  private let surface: any SwitcherSurface

  /// The remembered row for the current query, if one applies: the panel
  /// is filtering, the query is non-empty, and the memory holds its key.
  /// Membership in the shown rows is checked by the caller, so this asks
  /// nothing twice and survives matcher changes.
  private var rememberedID: WindowItem.Identifier? {
    // Synced here rather than in `didSet`: nested edits of the
    // settings skip `didSet`, and the cap must hold for them too.
    shortcutMemory.maxLength = searchSettings.shortcutMemoryLength
    guard isActive, !state.query.isEmpty else { return nil }
    return shortcutMemory.lookup(query: state.query)
  }

  /// The rows one list shows, in drawing order. Read through the layout,
  /// so the modes keep a row out and place it the same way whether the
  /// panel opened, a keystroke arrived, or a list was swapped in, and the
  /// choice and the drawing read one order in both orderings.
  private func shown(in windows: [WindowItem]) -> [WindowItem] {
    PanelLayout.make(
      rows: windows,
      modes: displayModes,
      query: state.query,
      exclusions: exclusionRules,
      fuzzy: searchSettings.fuzzyMatchEnabled,
      ordering: searchSettings.ordering,
      memory: rememberedID,
      owner: scope.narrowedOwner,
      grouping: grouping
    ).rows
  }

  /// Narrows the rows, puts the remembered row first in its section,
  /// follows the choice onto them, and tells the panel, drawing once.
  /// The exits resolve off the whole shown list: identities are unique,
  /// so a narrowed row reads back as itself either way.
  private func apply() {
    let matched = shownWindows
    let matchedList = matched.map(\.id)
    let chosen = state.resolveSelection(matched: matchedList, incoming: selection.chosenID)
    selection.retarget(to: matchedList, selecting: chosen)
    surface.updateList(windows: matched, selecting: selection.chosenID, query: state.query, filterActive: isActive)
    lastSummary = FilterLogSummary(
      query: state.query,
      matchedCount: matched.count,
      totalCount: fullWindows.count
    )
  }

}
