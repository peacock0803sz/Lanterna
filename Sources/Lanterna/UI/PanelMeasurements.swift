/// One press, measured.
///
/// Whether the panel is fast enough is a number, not an impression, and this
/// is where that number is written down. The wording lives with the reading so
/// the two cannot drift apart.
struct HotkeyMeasurement: Sendable {
    let combination: HotkeyCombination
    /// From the press arriving to the call that puts the panel up returning.
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

    var summaryLine: String {
        var line = "panel shown \(Diagnostics.millisecondsText(elapsed)) ms "
            + "after \(combination.name) (\(entryCount) entries)"
        if let deliveryDelay {
            line += "; delivery \(Diagnostics.millisecondsText(deliveryDelay)) ms"
        }
        if gatheredOnDemand {
            line += "; gathered on the spot (no list held yet)"
        }
        return line
    }
}

/// One Command release, and what it did.
///
/// Committing and calling a press off are two different events: one is a
/// release landing on a panel that is up, the other a press given up on
/// before the panel ever appeared. They share a type all the same: they are
/// measured over the same span, they go to the same place, and all the line
/// has to do is let whoever reads it tell which of them happened. One type
/// puts the three wordings in one `switch`, where a single test can hold all
/// three apart; two types could only claim from the outside that they differ.
///
/// Holds two strings rather than the `WindowItem` they came from. The item
/// carries an `NSImage` and so is not `Sendable`, and the line needs nothing
/// from it but the names.
struct CommandReleaseMeasurement: Sendable {
    enum Outcome: Sendable, Equatable {
        /// The panel was up and showing a row. `displayTitle` rather than
        /// `windowTitle`: the latter may be empty or hold nothing but
        /// whitespace, and a line trailing off after an em dash is not steady
        /// enough wording to match on.
        case committed(appName: String, displayTitle: String)
        /// The panel was up with nothing in it.
        case nothingToCommit
        /// The panel had not appeared yet, so the press waiting for a list was
        /// called off instead. Kept apart from the case above because the two
        /// have different causes and different answers: one means the list was
        /// gathered and held nothing, the other that there was no list yet.
        case pressCalledOff
    }

    let outcome: Outcome
    /// From the release arriving to the call that hides the panel returning.
    /// The same way round as `HotkeyMeasurement.elapsed`, and for the same
    /// reason: it is the part a process can measure for itself. The called-off
    /// case hides nothing, so there it runs to the press being let go of.
    let elapsed: Duration

    /// Said of an application whose name flattened away to nothing, which
    /// takes a name of spaces alone — the one shape the window enumeration's
    /// own fallback does not rule out. A line naming nobody is worse than one
    /// saying so, which is the reasoning behind that fallback's `pid N` too.
    private static let unnamedApplication = "an unnamed application"

    var summaryLine: String {
        let timing = "\(Diagnostics.millisecondsText(elapsed)) ms after Command was released"
        switch outcome {
        case let .committed(appName, displayTitle):
            let name = Self.oneLine(appName, fallback: Self.unnamedApplication)
            let title = Self.oneLine(displayTitle, fallback: name)
            return "committed \(name) — \(title) \(timing)"
        case .nothingToCommit:
            return "committed nothing \(timing) (the list was empty)"
        case .pressCalledOff:
            return "press called off \(timing), before the panel appeared"
        }
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
    private static func oneLine(_ text: String, fallback: String) -> String {
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
