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
    func begin(fullWindows: [WindowItem], filtering: Bool = false) {
        self.fullWindows = fullWindows
        state = FilterState()
        state.previousMatchedIDs = Set(fullWindows.map(\.id))
        lastSummary = FilterLogSummary(query: "", matchedCount: fullWindows.count, totalCount: fullWindows.count)
        isActive = filtering
    }

    /// Switches filtering on for the panel that is up.
    func activate() {
        isActive = true
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

    /// Narrows the rows, follows the choice onto them, and tells the panel,
    /// drawing once. The exits resolve off the whole shown list: identities
    /// are unique, so a narrowed row reads back as itself either way.
    private func apply() {
        let matched = WindowFilter.matching(state.query, against: fullWindows)
        let matchedIDs = matched.map(\.id)
        let chosen = state.resolveSelection(matched: matchedIDs, incoming: selection.chosenID)
        selection.retarget(to: matchedIDs, selecting: chosen)
        surface.updateList(windows: matched, selecting: selection.chosenID, query: state.query)
        lastSummary = FilterLogSummary(
            query: state.query,
            matchedCount: matched.count,
            totalCount: fullWindows.count
        )
    }
}
