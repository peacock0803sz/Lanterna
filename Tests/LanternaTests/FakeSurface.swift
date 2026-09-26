import Darwin
@testable import Lanterna

/// Stands in for the panel. A real one needs a window server. A screen would
/// show that a panel appeared, but not which list it was given, nor that it
/// appeared once rather than twice, and those are what this records.
///
/// In a file of its own for the reason `FakeKeyChannel` is: the shared file
/// is within twenty-odd lines of the length the linter allows, and a double
/// that needs nothing from the others has no reason to be charged to that
/// budget.
@MainActor
final class FakeSurface: SwitcherSurface {
    /// Every call in the order it came, so a test can say that keys were
    /// asked for after the panel went up and not before.
    enum Call: Equatable {
        case present(selecting: WindowItem.Identifier?)
        case takeKeys
        case showSelection(WindowItem.Identifier?)
        case updateList(selecting: WindowItem.Identifier?, query: String, filterActive: Bool)
        case dismiss
    }

    private(set) var calls: [Call] = []
    private(set) var presentedLists: [[WindowItem]] = []
    /// Every narrowed list the panel was told to swap in, in order.
    private(set) var updatedLists: [[WindowItem]] = []
    /// The choice and the query each swap carried beside the rows.
    private(set) var updatedSelections: [WindowItem.Identifier?] = []
    private(set) var updatedQueries: [String] = []
    /// Whether the filter chrome was on for each swap.
    private(set) var updatedActives: [Bool] = []
    /// Whether each appearance opened with the filter chrome on.
    private(set) var presentedActives: [Bool] = []
    /// The row each appearance was told to draw as chosen.
    private(set) var presentedSelections: [WindowItem.Identifier?] = []
    /// Every row the panel was told to redraw as chosen, in order. The count
    /// matters as much as the values: redrawing a selection must not go
    /// through `present`, and a test can only tell those apart by which
    /// record grew.
    private(set) var shownSelections: [WindowItem.Identifier?] = []
    private(set) var takeKeysCount = 0
    private(set) var dismissCount = 0
    /// Every failure note shown, in order.
    private(set) var notices: [String] = []
    /// How many times the note was taken down.
    private(set) var clearedNotices = 0
    /// The note on screen now, if any. A swapped list takes it down, the
    /// way the real panel redraws without it.
    private(set) var currentNotice: String?
    var isPresented = false

    /// Whether presses are reaching the panel.
    ///
    /// Settable, because this is the one seam through which a test stages
    /// key status being lost while a panel is up. There is no second way in:
    /// a lost-and-regained answer that could be injected somewhere else
    /// would be a second record of one thing.
    var isTakingKeys = false

    /// What `takeKeys()` answers.
    ///
    /// Separate from the flag above, and it has to be. Implementing the ask
    /// as a read of `isTakingKeys` would answer no for ever once a test had
    /// staged a loss, so no test could stage a recovery; answering yes always
    /// would make three failures in a row impossible to stage. Both are cases
    /// the panel has to be held to.
    var takeKeysSucceeds = true

    /// Run inside `dismiss()`, before it returns.
    ///
    /// Lets a test make the panel's disappearance cost something it can see.
    /// A stepping clock gives every reading the same weight, so a figure that
    /// is meant to span the dismissal and one that stops just short of it come
    /// out identical — one tick either way. Charging the dismissal its own tick
    /// is what separates them.
    var onDismiss: (@MainActor () -> Void)?

    func present(windows: [WindowItem], selecting: WindowItem.Identifier?, filterActive: Bool = false) {
        presentedLists.append(windows)
        presentedActives.append(filterActive)
        presentedSelections.append(selecting)
        calls.append(.present(selecting: selecting))
        isPresented = true
    }

    func takeKeys() -> Bool {
        takeKeysCount += 1
        calls.append(.takeKeys)
        isTakingKeys = takeKeysSucceeds
        return takeKeysSucceeds
    }

    func showSelection(_ id: WindowItem.Identifier?) {
        shownSelections.append(id)
        calls.append(.showSelection(id))
    }

    func updateList(
        windows: [WindowItem],
        selecting: WindowItem.Identifier?,
        query: String,
        filterActive: Bool
    ) {
        updatedLists.append(windows)
        updatedSelections.append(selecting)
        updatedQueries.append(query)
        updatedActives.append(filterActive)
        calls.append(.updateList(selecting: selecting, query: query, filterActive: filterActive))
        currentNotice = nil
    }

    func showNotice(_ text: String) {
        notices.append(text)
        currentNotice = text
    }

    func clearNotice() {
        clearedNotices += 1
        currentNotice = nil
    }

    func dismiss() {
        dismissCount += 1
        calls.append(.dismiss)
        isPresented = false
        // A panel ordered off the screen is no longer taking anything, and a
        // stand-in that went on saying it was would let a test pass that the
        // real one could not.
        isTakingKeys = false
        onDismiss?()
    }
}
