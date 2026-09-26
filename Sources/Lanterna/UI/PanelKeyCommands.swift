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
/// Holds no state of its own. Everything it needs to answer a press belongs
/// to something else — the panel, the chosen row, the ways out — and a copy
/// of any of it here would be a second record of one thing.
@MainActor
final class PanelKeyCommands {
    private let surface: any SwitcherSurface
    private let selection: PanelSelection
    private let wayOut: PanelExit
    private let filter: PanelFilter
    private let now: @MainActor () -> ContinuousClock.Instant
    /// Handed the row chosen as the key is pressed, so a choice moved
    /// before the operation gets its turn does not change its target.
    private let operate: (@Sendable @MainActor (WindowOperation, WindowItem.Identifier?) -> Void)?

    init(
        surface: any SwitcherSurface,
        selection: PanelSelection,
        wayOut: PanelExit,
        now: @escaping @MainActor () -> ContinuousClock.Instant,
        operate: (@Sendable @MainActor (WindowOperation, WindowItem.Identifier?) -> Void)? = nil
    ) {
        self.surface = surface
        self.selection = selection
        self.wayOut = wayOut
        filter = PanelFilter(selection: selection, surface: surface)
        self.now = now
        self.operate = operate
    }

    /// Starts an appearance over the whole ordered list, filtering only
    /// when the appearance asked for it.
    func beginFiltering(fullWindows: [WindowItem], filtering: Bool = false) {
        filter.begin(fullWindows: fullWindows, filtering: filtering)
    }

    /// Gives the appearance up; the next one starts empty either way.
    func endFiltering() {
        filter.reset()
    }

    /// Swaps the rows on screen for a list an operation hands over — its
    /// optimistic look, the reconciled list, or the look wound back —
    /// keeping the query and the commit's view of the appearance on the
    /// same rows, and moves the choice to where the anchor stood among the
    /// shown rows.
    func replacePresentedList(_ windows: [WindowItem], choosingWhere anchor: ChoiceAnchor) {
        filter.replace(fullWindows: windows, choosingWhere: anchor)
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

    /// Whether filtering answers keystrokes right now. The presenter asks
    /// before sending keystrokes here and before treating a released
    /// Command as anything.
    var isFilteringActive: Bool {
        filter.isActive
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
        // A new press answers the old failure: the note goes before
        // anything the press means is done.
        surface.clearNotice()
        switch PanelKeyInput.action(for: keystroke) {
        case .selectNext:
            selection.moveToNext()
        case .selectPrevious:
            selection.moveToPrevious()
        case let .cancel(key):
            // Escape clears the query first and only cancels on an empty
            // one. The table cannot tell the two apart: it keeps no state,
            // and the filter is where the question is answered.
            if key == .escape, filter.clear() {
                break
            }
            wayOut.cancel(by: key, since: startedAt, filter: filter.logSummary())
        case let .commit(key):
            wayOut.commit(by: key, naming: selection.chosenID, since: startedAt, filter: filter.logSummary())
        case let .windowOperation(operation):
            operate?(operation, selection.chosenID)
        case let .filterText(text):
            filter.append(text)
        case .filterBackspace:
            filter.removeLast()
        case .absorb:
            break
        }
        return .absorbed
    }
}
