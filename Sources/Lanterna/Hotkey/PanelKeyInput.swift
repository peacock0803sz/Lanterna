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

    /// What the keyboard made of the press, ignoring the modifiers held with
    /// it, or nothing when it made nothing. Read where the press arrives
    /// rather than decided later: meaning is still worked out by key code,
    /// and this is only what a row that means filtering carries with it.
    let characters: String

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
    init(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isARepeat: Bool,
        characters: String = ""
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        self.isARepeat = isARepeat
        self.characters = characters
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
    /// An operation on the chosen row. Read before the filtering row: an
    /// operation key held with Command is an operation even where its
    /// letter would type, while any other Command letter still narrows.
    case windowOperation(WindowOperation)
    /// A letter or a confirmed string: narrows the list on screen.
    case filterText(String)
    /// Backspace: shortens the query by one character.
    case filterBackspace
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
    /// Begins delivering presses, and answers whether they will arrive. What
    /// the handler answers decides what becomes of each event.
    ///
    /// Every implementation has to take off whatever it started before, and to
    /// do it before anything new is put in place. Two monitors over one
    /// keyboard would ask the same question twice and act on both answers —
    /// one press arriving as two, for as long as both are up.
    ///
    /// The requirement is set out here, where every implementation can be held
    /// to it, rather than in the body of the one that happens to keep it — the
    /// same reason `EventTapControlling` states what it needs of every tap
    /// instead of leaving it to the callers. A stand-in that merely swapped its
    /// handler over would be looser than the thing it stands in for, and a rule
    /// living only inside the real one gives nobody a place to notice that.
    ///
    /// `false` means no monitor was installed, and nothing else in the process
    /// says so. A run without one looks exactly like a working one from the
    /// outside until a key is pressed: the panel still appears, the presenter
    /// still holds an opinion about every keystroke, and not one of them is
    /// ever put to it — the presses reach the frontmost application and type
    /// into whatever is there. So this is the only notice there is, and it is
    /// not one a caller may drop by accident. No `@discardableResult`, for
    /// that reason: a caller that means to throw the answer away spells it out
    /// with `_ =` and says why, the way the deliberate discards in
    /// `AppDelegate` do.
    func start(handler: @escaping @MainActor (PanelKeystroke) -> PanelKeyDisposition) -> Bool

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
    /// Putting a monitor on this process's event stream: a mask, a block, and
    /// back either a token or nothing.
    ///
    /// The nothing is the whole reason this is a parameter. AppKit's call is
    /// documented to hand back `nil` when it declines, and there is no way to
    /// make it decline on demand — nor any way, with the real call wired
    /// straight in, to see that a second start takes the first monitor off
    /// before installing the next. Both are claims this class makes, and
    /// neither could be put to a test.
    ///
    /// Closures rather than a protocol, which is where this parts company with
    /// `EventTapControlling`. That one stands for a thing with a life of its
    /// own: it keeps a tap between calls, and a call can leave the next one
    /// with a different answer to give — so a type is what it takes to stand
    /// in for it. This is two free functions, and the shape the rest of this
    /// project uses for those is a closure with the real call as its default,
    /// as `ModifierKeyMonitor` does for the clock and for the writing of
    /// lines.
    typealias InstallMonitor =
        @MainActor (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?

    /// Taking one back off, which AppKit will do given the token and nothing
    /// else.
    typealias RemoveMonitor = @MainActor (Any) -> Void

    private let installMonitor: InstallMonitor
    private let removeMonitor: RemoveMonitor

    /// AppKit hands back an opaque token, and it is the only way to take the
    /// monitor off again.
    private var monitor: Any?

    /// The real calls are the defaults, so the app builds one of these with no
    /// arguments and nothing outside a test ever learns there is a seam here.
    init(
        installMonitor: @escaping InstallMonitor = { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        removeMonitor: @escaping RemoveMonitor = { NSEvent.removeMonitor($0) }
    ) {
        self.installMonitor = installMonitor
        self.removeMonitor = removeMonitor
    }

    /// Subscribes to presses only.
    ///
    /// Not releases, and not the modifier keys. The one thing this layer
    /// needs to know is that a key went down; the modifiers are already
    /// watched a layer below, and a wider subscription would widen what this
    /// layer reads of somebody's typing for no answer it needs.
    ///
    /// Keeps the replacement `PanelKeyChannel` requires by stopping first, in
    /// the shape the window list's loop uses. Why it is required is set out
    /// with the requirement rather than said again here: two spellings of one
    /// rule are two things that can drift apart.
    ///
    /// The answer is read back from what AppKit handed over rather than
    /// assumed from the asking, the way `SystemEventTap.start()` reads its tap
    /// back. Installing a monitor is a request, and this one is documented to
    /// come back empty-handed; the caller has no second way of finding that
    /// out, because a process with no monitor goes on behaving exactly like one
    /// with a monitor right up until somebody presses a key.
    func start(handler: @escaping @MainActor (PanelKeystroke) -> PanelKeyDisposition) -> Bool {
        stop()
        monitor = installMonitor(.keyDown) { event in
            let keystroke = PanelKeystroke(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags,
                isARepeat: event.isARepeat,
                characters: event.charactersIgnoringModifiers ?? ""
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
        return monitor != nil
    }

    func stop() {
        if let monitor {
            removeMonitor(monitor)
        }
        // Let go whether or not there was one, so a second stop has nothing to
        // hand back. AppKit has already taken this token, and handing it the
        // same one twice is asking it to remove a monitor it no longer knows
        // about.
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
        if let early = earlyMeaning(of: keystroke) {
            return early
        }
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
        // The one row of this table that asks about modifiers. A bare full
        // stop is somebody typing, and typing must not cancel; the
        // operations asked ahead of the table hold Command for the same
        // reason. Every other row ignores them on purpose: the ordinary
        // press is made with Command still down, while a run whose modifier
        // monitor never started sees the same keys arrive bare after Command
        // has been let go, and both have to work the same way.
        case kVK_ANSI_Period where keystroke.modifiers.contains(.command):
            return .cancel(.commandPeriod)
        case kVK_Delete:
            return .filterBackspace
        default:
            // Going by key code and not by the character is what keeps this
            // whole table independent of the input source and the physical
            // layout — in kana mode the full stop's key reports 。 What the
            // key made is only read here, where a row means filtering, and
            // nowhere else in the table.
            guard let text = WindowFilter.allowedText(keystroke.characters) else {
                return .absorb
            }
            return .filterText(text)
        }
    }

    /// Tab and the window operations, asked ahead of the table below. Tab
    /// first, and whatever is held with it: Carbon has claimed Cmd+Tab and
    /// Shift+Cmd+Tab, and the selection moves through that route, so a Tab
    /// acted on here as well would move the selection two rows for one
    /// press. Whether Carbon lets a Tab through at all is not the point:
    /// if it does not, this row costs a comparison and nothing else.
    /// The operations go by key code and Command held, as the full stop
    /// does: what the key would type is not asked. Out here so the table
    /// below stays within the complexity the linter allows.
    private static func earlyMeaning(of keystroke: PanelKeystroke) -> PanelKeyAction? {
        guard Int(keystroke.keyCode) != kVK_Tab else { return .absorb }
        if let operation = operation(of: keystroke) {
            return .windowOperation(operation)
        }
        return nil
    }

    private static func operation(of keystroke: PanelKeystroke) -> WindowOperation? {
        guard keystroke.modifiers.contains(.command) else { return nil }
        switch Int(keystroke.keyCode) {
        case kVK_ANSI_W:
            return .closeWindow
        case kVK_ANSI_Q:
            return .quitApplication
        case kVK_ANSI_H:
            return .hideApplication
        case kVK_ANSI_M:
            return .minimizeWindow
        default:
            return nil
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
        case .selectNext, .selectPrevious, .filterText, .filterBackspace:
            self
        case .commit, .cancel, .windowOperation, .absorb:
            .absorb
        }
    }
}
