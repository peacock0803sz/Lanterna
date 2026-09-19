import AppKit
import Carbon.HIToolbox

/// One key press, as it arrived, before anything has decided what it means.
///
/// Always makeable. Nothing here can fail, and no key is turned away at the
/// door: a press with no meaning given to it still reaches the presenter and
/// is still absorbed there. Deciding at the door instead would leave the
/// keys that mean nothing unable to be put through a test at all, and "a key
/// that means nothing does nothing" is one of the things that has to be shown
/// rather than assumed.
struct PanelKeystroke: Equatable, Sendable {
    /// Where the key sits on the keyboard, which is what this layer goes by.
    let keyCode: UInt16

    /// The modifiers held with it, already narrowed to the ones that are the
    /// same on every keyboard.
    let modifiers: NSEvent.ModifierFlags

    /// Whether the keyboard produced this by repeating a key that is being
    /// held down, rather than the user pressing it.
    let isARepeat: Bool

    /// Narrows the modifiers here rather than where they are read.
    ///
    /// A raw `modifierFlags` carries bits that say which physical key was
    /// used and other device-dependent detail, so two presses that mean the
    /// same thing can hold different values. Narrowing at the one place a
    /// keystroke comes into being means every keystroke in the process is
    /// already narrowed, including the ones a test injects; narrowing where
    /// the flags are read would leave the injected ones holding a value the
    /// real ones never hold, and the next reader of `modifiers` would be the
    /// one to find out.
    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isARepeat: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        self.isARepeat = isARepeat
    }
}

/// Which key committed, so the line written can say so.
///
/// The two are kept apart because which physical key arrived is the evidence
/// for going by key code at all, and a log that flattened them would throw
/// that evidence away.
enum CommitKey: Equatable, Sendable {
    case returnKey
    case keypadEnter
}

/// Which key cancelled, kept apart for the reason the commit keys are.
enum CancelKey: Equatable, Sendable {
    case commandPeriod
    case escape
}

/// What a keystroke means to a panel that is up.
enum PanelKeyAction: Equatable, Sendable {
    case selectNext
    case selectPrevious
    case commit(CommitKey)
    case cancel(CancelKey)
    /// No meaning was given to this key. It is swallowed all the same.
    case absorb
}

/// What became of the event the keystroke came in on.
///
/// Not the same question as what the keystroke meant: a key with no meaning
/// is still absorbed, because a panel that is up takes the whole keyboard.
enum PanelKeyDisposition {
    /// The monitor answers with nothing, and the event goes no further.
    case absorbed
    /// The monitor hands the event back, and it carries on to whatever would
    /// have had it.
    case passedThrough
}

/// Where key presses reach this process from while a panel is up.
///
/// Behind a protocol for the reason `EventTapControlling` is: the real one
/// asks AppKit to put a monitor on this process's event stream, and a test
/// process wants to hand a keystroke over without one.
@MainActor
protocol PanelKeyChannel {
    /// Begins delivering presses. The answer decides what becomes of each
    /// event.
    func start(handler: @escaping @MainActor (PanelKeystroke) -> PanelKeyDisposition)

    /// Stops delivering.
    func stop()
}

/// The real channel: AppKit's own monitor over the presses this process is
/// handed.
///
/// Local and not global. A global monitor watches the whole machine's
/// keyboard and needs the grant that goes with that; this one sees only what
/// the system has already decided belongs to this process, which is what
/// makes it free of any permission and free of any reach beyond the panel.
@MainActor
final class LocalKeyEventChannel: PanelKeyChannel {
    /// AppKit hands back an opaque token, and it is the only way to take the
    /// monitor off again.
    private var monitor: Any?

    /// Subscribes to presses only.
    ///
    /// Not releases, and not the modifier keys. The one thing this layer
    /// needs to know is that a key went down; the modifiers are already
    /// watched a layer below, and a wider subscription would widen what this
    /// layer reads of somebody's typing for no answer it needs.
    ///
    /// Replaces whatever it started before, the way the window list's loop
    /// does. Two monitors over one keyboard would ask the same question twice
    /// and act on both answers.
    func start(handler: @escaping @MainActor (PanelKeystroke) -> PanelKeyDisposition) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keystroke = PanelKeystroke(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                isARepeat: event.isARepeat
            )
            // AppKit delivers these on the main thread, so this is the main
            // actor's executor; nothing weaker than a trap is wanted if that
            // ever stops being true.
            //
            // Only the answer comes back out, and it has to be that way
            // round: an event is not something the language will let cross
            // between them, so handing the event in and taking it back would
            // not compile. Nothing is lost by it — the event is still here to
            // hand back, and what the decision needs of it was read above.
            //
            // Nothing is decided in here either. Whether a panel is up is
            // known in one place, and this is not it; a second record of that
            // here would be a second thing to keep true.
            let disposition = MainActor.assumeIsolated { handler(keystroke) }
            switch disposition {
            case .absorbed:
                return nil
            case .passedThrough:
                return event
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

/// Turning a key press into what it means, and nothing else.
///
/// A namespace rather than a type with state: there is nothing to remember
/// between one press and the next. The whole of the mapping is a pure
/// function, so every row of the table below can be held to without a window
/// server, a clock or a panel.
enum PanelKeyInput {
    /// What the panel should do about this press.
    static func action(for keystroke: PanelKeystroke) -> PanelKeyAction {
        let action = meaning(of: keystroke)
        guard keystroke.isARepeat else { return action }
        return action.whenTheKeyboardIsRepeating
    }

    /// The table itself, with the repeating question left out.
    ///
    /// Split from `action(for:)` so that neither half grows to where it has
    /// to be read twice. A `switch` over the key codes plus the test above
    /// would sit against the complexity limit with no room for the row that
    /// gets added next, and this codebase suppresses no lint rule.
    private static func meaning(of keystroke: PanelKeystroke) -> PanelKeyAction {
        // Tab first, and whatever is held with it. Carbon has claimed Cmd+Tab
        // and Shift+Cmd+Tab and moves the selection through that route, so a
        // Tab acted on here as well would move the selection two rows for one
        // press. Whether Carbon lets a Tab through to this process's key
        // window at all is not the point: if it does not, this row costs a
        // comparison and nothing else.
        guard Int(keystroke.keyCode) != kVK_Tab else { return .absorb }
        switch Int(keystroke.keyCode) {
        case kVK_DownArrow:
            return .selectNext
        case kVK_UpArrow:
            return .selectPrevious
        case kVK_Return:
            return .commit(.returnKey)
        case kVK_ANSI_KeypadEnter:
            return .commit(.keypadEnter)
        case kVK_Escape:
            return .cancel(.escape)
        // The one row that asks about modifiers at all. A bare full stop is
        // somebody typing, and typing must not cancel. Every other row
        // ignores them on purpose: the ordinary press is made with Command
        // still down, while a run whose modifier monitor never started sees
        // the same keys arrive bare after Command has been let go, and both
        // have to work the same way.
        case kVK_ANSI_Period where keystroke.modifiers.contains(.command):
            return .cancel(.commandPeriod)
        default:
            // Every other key, including the ones that would type something.
            // Going by key code and not by the character is what keeps this
            // whole table independent of the input source and the physical
            // layout — in kana mode the full stop's key reports 。
            return .absorb
        }
    }
}

private extension PanelKeyAction {
    /// What this becomes when the press was the keyboard repeating a held key
    /// rather than the user pressing one.
    ///
    /// Moving the selection is the one thing worth repeating: holding an
    /// arrow down to run along a list is how a list is meant to be used.
    /// Committing or cancelling twice is not a thing anyone asks for, and the
    /// second one would land on whatever the first one left behind.
    var whenTheKeyboardIsRepeating: PanelKeyAction {
        switch self {
        case .selectNext, .selectPrevious:
            self
        case .commit, .cancel, .absorb:
            .absorb
        }
    }
}
