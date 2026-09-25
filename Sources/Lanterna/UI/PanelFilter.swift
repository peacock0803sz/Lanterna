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
    func begin(fullWindows: [WindowItem]) {
        self.fullWindows = fullWindows
        state = FilterState()
        state.previousMatchedIDs = Set(fullWindows.map(\.id))
        lastSummary = FilterLogSummary(query: "", matchedCount: fullWindows.count, totalCount: fullWindows.count)
    }

    /// Gives the appearance up; the next one starts empty either way.
    func reset() {
        fullWindows = []
        state = FilterState()
        lastSummary = FilterLogSummary(query: "", matchedCount: 0, totalCount: 0)
    }

    /// What the commit and cancel lines will say about this appearance.
    ///
    /// Read at the exits, which write their lines after the closing: the
    /// value travels with the call, so no state outlives the panel it
    /// describes.
    func logSummary() -> FilterLogSummary {
        lastSummary
    }

    /// Narrows one keystroke further.
    func append(_ text: String) {
        state.append(text)
        apply()
    }

    /// Shortens the query by one character.
    func removeLast() {
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
        guard isFiltering else { return false }
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
