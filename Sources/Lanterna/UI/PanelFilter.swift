/// Where the operated row stood before a list was swapped: the row, and the
/// whole list it stood in. The filter counts the place among the rows it
/// shows.
struct ChoiceAnchor {
    let id: WindowItem.Identifier
    let stoodIn: [WindowItem]
}

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
    private var fullWindows: [WindowItem] = []
    private var state = FilterState()
    private var lastSummary = FilterLogSummary(query: "", matchedCount: 0, totalCount: 0)
    /// Whether keystrokes narrow the list right now. Set only by the filter
    /// invocation; a panel shown any other way leaves it off, and typing is
    /// swallowed as before.
    private(set) var isActive = false
    /// How the special kinds show. Read at launch from the config file;
    /// the panel keeps the rows and this decides which reach the screen.
    var displayModes = DisplayModes.defaults
    private let selection: PanelSelection
    private let surface: any SwitcherSurface

    init(selection: PanelSelection, surface: any SwitcherSurface) {
        self.selection = selection
        self.surface = surface
    }

    /// Whether a query is narrowing the list right now.
    var isFiltering: Bool {
        !state.query.isEmpty
    }

    /// Starts an appearance over the whole ordered list, remembering nothing.
    /// Filtering answers keystrokes only when the appearance asked for it.
    /// Draws nothing: the caller opens the choice and the panel on
    /// `shownWindows`, so the modes narrow the list before either sees it.
    func begin(fullWindows: [WindowItem], filtering: Bool = false) {
        self.fullWindows = fullWindows
        state = FilterState()
        let shown = shownWindows
        state.previousMatchedIDs = Set(shown.map(\.id))
        lastSummary = FilterLogSummary(query: "", matchedCount: shown.count, totalCount: fullWindows.count)
        isActive = filtering
    }

    /// The rows on screen: the whole list narrowed by the query and the
    /// display modes, in the order the panel draws them. The whole list
    /// stays underneath, so a query can still bring back a row the modes
    /// keep out.
    var shownWindows: [WindowItem] {
        shown(in: fullWindows)
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

    /// What the commit and cancel lines will say about this appearance.
    ///
    /// Read at the exits, which write their lines after the closing: the
    /// value travels with the call, so no state outlives the panel it
    /// describes.
    func logSummary() -> FilterLogSummary {
        lastSummary
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

    /// The rows one list shows under the current query and modes, in the
    /// order the panel draws them. Every entry narrows through here, so the
    /// modes keep a row out and place it the same way whether the panel
    /// opened, a keystroke arrived, or a list was swapped in.
    private func shown(in windows: [WindowItem]) -> [WindowItem] {
        DisplayModes.displayOrdered(windows, modes: displayModes, query: state.query)
    }

    /// Narrows the rows, follows the choice onto them, and tells the panel,
    /// drawing once. The exits resolve off the whole shown list: identities
    /// are unique, so a narrowed row reads back as itself either way.
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
