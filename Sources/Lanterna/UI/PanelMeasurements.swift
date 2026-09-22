/// One press, measured.
///
/// Whether the panel is fast enough is a number, not an impression, and this
/// is where that number is written down. The wording lives with the reading so
/// the two cannot drift apart.
struct HotkeyMeasurement: Sendable {
    let combination: HotkeyCombination
    /// From the press arriving to the panel being up and having been asked for
    /// the keyboard. Asking is a call of its own, separate from the one that
    /// puts the panel up, and it goes to the window server — so it is inside
    /// the budget, not beside it.
    ///
    /// Not the delivery before it and not the compositing after it: a process
    /// can see neither, and a budget that included them could not be checked
    /// from inside.
    let elapsed: Duration
    let entryCount: Int
    /// How long the press spent between being recorded by the system and
    /// arriving here. Observed and reported, but outside the budget above,
    /// because nothing this app does changes it.
    let deliveryDelay: Duration?
    /// Whether the list had to be gathered on the spot, which is the one case
    /// where the reading above says more about the list than about the panel.
    let gatheredOnDemand: Bool

    /// Whether key presses were reaching the panel once it was up.
    ///
    /// Carried with no default value, so that every appearance has to answer
    /// it. An answer that could be left out would be left out.
    let becameKey: Bool

    var summaryLine: String {
        var line = "panel shown \(Diagnostics.millisecondsText(elapsed)) ms "
            + "after \(combination.name) (\(entryCount) entries)"
        if let deliveryDelay {
            line += "; delivery \(Diagnostics.millisecondsText(deliveryDelay)) ms"
        }
        if gatheredOnDemand {
            line += "; gathered on the spot (no list held yet)"
        }
        // Said every time, both ways round, rather than only when something
        // went wrong. A phrase that appears only on the bad run cannot be
        // told from a binary too old to know the phrase at all, and reading
        // a log from the wrong build is a way this project has been misled
        // before. One that is always there doubles as the mark of which
        // build wrote the line.
        //
        // Appended at the end, where nothing is counting from. The existing
        // check on how long the panel took reads the third whitespace-
        // separated field and is not anchored to the end of the line, so
        // everything already being counted goes on reading the same.
        line += becameKey
            ? "; taking keys"
            : "; not taking keys (they reach the frontmost application)"
        return line
    }
}

/// One appearance ending, and what ended it.
///
/// Committing, calling a press off and cancelling are different events: a
/// release or a key landing on a panel that is up, a press given up on before
/// the panel ever appeared, and a key saying not this one. They share a type
/// all the same: they are measured over the same span, they go to the same
/// place, and all the line has to do is let whoever reads it tell which of
/// them happened. One type puts the wordings in one `switch`, where a single
/// test can hold them apart; separate types could only claim from the outside
/// that they differ.
///
/// Named for the exit rather than for the release, because the release is now
/// one of three things that can reach here.
///
/// Holds the names and the identity rather than the `WindowItem` they came
/// from. The item carries an `NSImage` and so is not `Sendable`, and a line
/// needs nothing else off it: the names for a person to read, the identity
/// because two rows can share a pair of names.
struct PanelExitMeasurement: Sendable {
    /// What ended the appearance, and the only place that is recorded.
    ///
    /// Deliberately not also carried by `Outcome`. A `.cancelled(by:)` case
    /// holding the key as well would let `.cancelled(by: .escape)` sit beside
    /// a trigger saying Return: a pair no run can produce, which the type
    /// would accept and which `summaryLine` could resolve two ways depending
    /// on which of the two it read first. Both ways would pass every test
    /// there is, because no test can build a pair that cannot happen without
    /// being written to do exactly that.
    ///
    /// Borrows `CommitKey` and `CancelKey` rather than restating them.
    /// Which keys commit and which cancel is `PanelKeyInput`'s vocabulary,
    /// settled where a keystroke is given its meaning; a second spelling here
    /// would make the presenter's hand-off from one to the other a place
    /// where the wrong key can be named in a way that still type-checks.
    ///
    /// `Trigger` itself stays here, with the wording it decides. Letting go of
    /// Command is not a keystroke and has no place among the commit keys, and
    /// the phrases below are what this file exists to pin.
    enum Trigger: Equatable, Sendable {
        case commandRelease
        case commitKey(CommitKey)
        case cancelKey(CancelKey)

        /// How a line names the thing that ended the appearance.
        ///
        /// Return and the keypad's Enter are worded apart. Which physical key
        /// arrived is the evidence for going by key code at all, and a log
        /// that flattened the two would throw that evidence away.
        var phrase: String {
            switch self {
            case .commandRelease: "Command was released"
            case .commitKey(.returnKey): "Return"
            case .commitKey(.keypadEnter): "keypad Enter"
            // Spelled out rather than written `⌘.`: a full stop is a regular
            // expression's wildcard, and one at the end of a line of prose
            // reads as punctuation.
            case .cancelKey(.commandPeriod): "Cmd+Period"
            case .cancelKey(.escape): "Escape"
            }
        }

        /// Whether the appearance ended in a take. Only those endings have a
        /// switch result to report; a cancellation must never reach one.
        var isCommit: Bool {
            switch self {
            case .commandRelease, .commitKey:
                return true
            case .cancelKey:
                return false
            }
        }
    }

    enum Outcome: Sendable, Equatable {
        /// The panel was up and showing a row. `displayTitle` rather than
        /// `windowTitle`: the latter may be empty or hold nothing but
        /// whitespace, and a line trailing off after an em dash is not steady
        /// enough wording to match on.
        ///
        /// The identity travels alongside the names because the names are
        /// not unique. Two windows of one application with nothing in their
        /// title bars give the same pair, and a log meant to show that the
        /// right row was taken cannot show it from a pair that two rows share.
        case committed(appName: String, displayTitle: String, id: WindowItem.Identifier)
        /// The panel was up with nothing in it.
        case nothingToCommit
        /// The panel had not appeared yet, so the press waiting for a list was
        /// called off instead. Kept apart from the case above because the two
        /// have different causes and different answers: one means the list was
        /// gathered and held nothing, the other that there was no list yet.
        ///
        /// Carries no key, and could not: a press waiting for its first list
        /// is let go of by Command coming up, and the keys that end an
        /// appearance only arrive while one is on screen.
        case pressCalledOff
        /// The user said not this one. No row is named — naming the row that
        /// happened to be highlighted would put a window's name on the one
        /// line whose meaning is that nobody chose it.
        ///
        /// An empty list cancels the same way a full one does, which is why
        /// there is no emptiness to tell here: nothing was going to be taken
        /// either way.
        case cancelled
    }

    let outcome: Outcome
    /// What ended the appearance. The line's last clause is read off this.
    let trigger: Trigger
    /// From the release or the keystroke arriving to the call that hides the
    /// panel returning. The same way round as `HotkeyMeasurement.elapsed`, and
    /// for the same reason: it is the part a process can measure for itself.
    /// The called-off case hides nothing, so there it runs to the press being
    /// let go of.
    let elapsed: Duration

    /// Said of an application whose name flattened away to nothing, which
    /// takes a name of spaces alone — the one shape the window enumeration's
    /// own fallback does not rule out. A line naming nobody is worse than one
    /// saying so, which is the reasoning behind that fallback's `pid N` too.
    private static let unnamedApplication = "an unnamed application"

    /// Switched on the pair and not on the outcome alone, because the pair is
    /// what has to be rejected. Every wording below can be reached from the
    /// outcome by itself — the trigger's words are already inside `timing` —
    /// so switching on the outcome would compile, read the same, and quietly
    /// print `cancelled ... after Command was released` for a combination no
    /// run produces. Naming both is what gives the six that cannot happen
    /// somewhere to be turned away.
    var summaryLine: String {
        let timing = "\(Diagnostics.millisecondsText(elapsed)) ms after \(trigger.phrase)"
        switch (outcome, trigger) {
        case let (.committed(appName, displayTitle, id), .commandRelease),
             let (.committed(appName, displayTitle, id), .commitKey):
            let row = Self.rowDescription(appName: appName, displayTitle: displayTitle, id: id)
            return "committed \(row) \(timing)"
        case (.nothingToCommit, .commandRelease), (.nothingToCommit, .commitKey):
            return "committed nothing \(timing) (the list was empty)"
        case (.pressCalledOff, .commandRelease):
            return "press called off \(timing), before the panel appeared"
        // Shares no word with any of the commit wordings, so one pattern tells
        // the two apart with nothing to disambiguate.
        case (.cancelled, .cancelKey):
            return "cancelled \(timing)"
        // The pairs that cannot happen, gathered in one place. Written out
        // rather than swept up by a `default`: a case added to either enum
        // then fails to build until somebody decides which side of this line
        // it falls on, where a `default` would take the new pair in silence
        // and say so only on the run that reached it.
        case (.committed, .cancelKey),
             (.nothingToCommit, .cancelKey),
             (.pressCalledOff, .commitKey),
             (.pressCalledOff, .cancelKey),
             (.cancelled, .commandRelease),
             (.cancelled, .commitKey):
            preconditionFailure("\(outcome) cannot have been brought about by \(trigger)")
        }
    }

    /// Names a row the way a line naming one has to: application, an em dash,
    /// window.
    ///
    /// Shared rather than copied, because the commit line above is no longer
    /// the only line that names a row — the panel closing for a release
    /// nothing reported names one too, into the same log. Two spellings of
    /// this would let one line flatten what it names and the other not, and
    /// the flattening below is the whole of what keeps a window title with a
    /// newline in it from printing as two lines of log.
    ///
    /// The window falls back to the application rather than to the unnamed
    /// application: a row whose title flattened away to nothing is still that
    /// application's row, and saying its name twice is truer than saying
    /// nobody's.
    ///
    /// The identity follows the names rather than replacing them, because a
    /// line is read by a person first. It is there because names are not
    /// unique: two untitled windows of one application read alike, and a
    /// reader checking that the highlighted row is the row that was taken
    /// would have nothing to check.
    ///
    /// The bare number and not the identity as Swift prints it. This type has
    /// no description of its own, so interpolating it would give
    /// `(window Identifier(windowID: 42))` — which reads as a spelling
    /// mistake and, worse, matches nothing a reader would search for, so a
    /// count of rows taken by mistake would come back zero either way.
    ///
    /// Placed before the timing and not after it. The existing check on how
    /// quickly a release was answered anchors on the end of the line, so
    /// anything appended there would take that anchor off and a check written
    /// against the last release would start failing against this one.
    static func rowDescription(
        appName: String,
        displayTitle: String,
        id: WindowItem.Identifier
    ) -> String {
        let name = oneLine(appName, fallback: unnamedApplication)
        return "\(name) — \(oneLine(displayTitle, fallback: name)) (window \(id.windowID))"
    }

    /// Flattens a name or title into something that can sit on one line.
    ///
    /// Window titles may contain newlines, and one event printing as two lines
    /// breaks the one-line-per-event promise, and with it any count taken by
    /// matching these lines. Control characters that are not whitespace
    /// go the same way: a bell or an escape in a title would otherwise reach a
    /// terminal reading the log.
    ///
    /// Characters that take up no space go the same way, though none of them
    /// reaches a terminal as anything. A zero width space hidden in an
    /// application name gives a line that reads correctly to the eye and
    /// matches nothing, and these lines are meant to be counted by matching
    /// them: the count would go quietly short rather than visibly wrong.
    ///
    /// So do the characters that reverse the reading order. One of them makes
    /// a terminal draw the rest of the line backwards, leaving the reader a
    /// duration they cannot read and wording the app never wrote — and a title
    /// mixing in a right-to-left script carries one with nobody meaning it.
    ///
    /// A character counts as invisible only when every part of it is, rather
    /// than when any part is: an emoji is held together by invisible
    /// characters, and the looser test would flatten a whole emoji to a space.
    ///
    /// Falling back when nothing is left is also what keeps a line from
    /// trailing off after a bare em dash.
    ///
    /// Two lines are counted on this now rather than one. The commit above and
    /// the panel closing for a release nothing reported both reach it through
    /// `rowDescription`, so neither can come to flatten what the other leaves
    /// alone — which is the whole reason that one goes through here.
    static func oneLine(_ text: String, fallback: String) -> String {
        let flattened = text
            .map { character -> String in
                let isInvisible = character.unicodeScalars.allSatisfy {
                    switch $0.properties.generalCategory {
                    case .control, .format:
                        true
                    default:
                        false
                    }
                }
                return character.isWhitespace || isInvisible ? " " : String(character)
            }
            .joined()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return flattened.isEmpty ? fallback : flattened
    }
}

/// What taking a row came to, written as the commit line's pair.
///
/// The commit line says which row was taken; this line says what taking it
/// came to. The two are written together with nothing between them, so one
/// appearance's end reads as one unit. The figure on both is the same span —
/// the commit's entrance to the panel going away, never the taking itself —
/// so the pair carries one number twice rather than two numbers to tell
/// apart.
struct SwitchMeasurement: Sendable {
    let appName: String
    let displayTitle: String
    let id: WindowItem.Identifier
    let outcome: ActivationOutcome
    let trigger: PanelExitMeasurement.Trigger
    let elapsed: Duration

    var summaryLine: String {
        precondition(trigger.isCommit, "a switch result cannot follow a cancellation")
        let row = PanelExitMeasurement.rowDescription(appName: appName, displayTitle: displayTitle, id: id)
        let timing = "\(Diagnostics.millisecondsText(elapsed)) ms after \(trigger.phrase)"
        switch outcome {
        case .switched:
            return "switched to \(row) \(timing)"
        case .failed(.windowGone):
            return "could not switch to \(row) (window gone) \(timing)"
        case .failed(.applicationGone):
            return "could not switch to \(row) (application gone) \(timing)"
        case .failed(.timedOut):
            return "could not switch to \(row) (timed out) \(timing)"
        case let .failed(.other(reason)):
            return "could not switch to \(row) (\(PanelExitMeasurement.oneLine(reason, fallback: "unknown"))) \(timing)"
        }
    }
}
