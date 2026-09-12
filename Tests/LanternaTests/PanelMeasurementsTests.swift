@testable import Lanterna
import Testing

/// The panel appearing quickly is the whole point of the feature, and this
/// line is the only record of whether it did, so its shape is pinned segment
/// by segment.
struct HotkeyMeasurementTests {
    private static func measurement(
        combination: HotkeyCombination = .forward,
        elapsed: Duration = .microseconds(4800),
        entryCount: Int = 12,
        deliveryDelay: Duration? = nil,
        gatheredOnDemand: Bool = false
    ) -> HotkeyMeasurement {
        HotkeyMeasurement(
            combination: combination,
            elapsed: elapsed,
            entryCount: entryCount,
            deliveryDelay: deliveryDelay,
            gatheredOnDemand: gatheredOnDemand
        )
    }

    /// No run produces this shape today: the delivery reading comes from two
    /// readings of one clock, neither of which can fail, so it is always
    /// there. It stays optional, and tested, so that if the reading ever does
    /// become fallible the line loses a segment instead of losing its meaning.
    @Test func withNothingOptionalTheLineIsTheTimingAlone() {
        #expect(
            Self.measurement().summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)"
        )
    }

    @Test func aMeasuredDeliveryFollowsTheTiming() {
        #expect(
            Self.measurement(deliveryDelay: .microseconds(1900)).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"
        )
    }

    /// A reading taken while the list was still being gathered says more about
    /// the list than about the panel, so it is marked rather than averaged in
    /// with the rest.
    @Test func gatheringOnTheSpotIsCalledOut() {
        #expect(
            Self.measurement(gatheredOnDemand: true).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)"
                + "; gathered on the spot (no list held yet)"
        )
    }

    @Test func bothOptionalSegmentsKeepTheirOrder() {
        #expect(
            Self.measurement(deliveryDelay: .microseconds(1900), gatheredOnDemand: true)
                .summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"
                + "; gathered on the spot (no list held yet)"
        )
    }

    @Test func theReverseCombinationNamesItself() {
        #expect(
            Self.measurement(combination: .reverse).summaryLine
                == "panel shown 4.8 ms after Shift+Cmd+Tab (12 entries)"
        )
    }

    /// Both timings round to one decimal place, so how long the panel took can
    /// be read off the line without arithmetic.
    @Test func timingsCarryExactlyOneDecimalPlace() {
        let line = Self.measurement(
            elapsed: .microseconds(71251),
            deliveryDelay: .zero
        ).summaryLine
        #expect(line == "panel shown 71.3 ms after Cmd+Tab (12 entries); delivery 0.0 ms")
    }
}

/// What a Command release says it did.
///
/// Three wordings, one of which is written every time the key is let go while
/// the panel is up or on its way. They are pinned here rather than where the
/// decision is made, so a reword shows up as a failure in the file that owns
/// the wording.
struct CommandReleaseMeasurementTests {
    private static func measurement(
        _ outcome: CommandReleaseMeasurement.Outcome,
        elapsed: Duration = .microseconds(4800)
    ) -> CommandReleaseMeasurement {
        CommandReleaseMeasurement(outcome: outcome, elapsed: elapsed)
    }

    @Test func aCommitNamesTheRowItTook() {
        #expect(
            Self.measurement(.committed(appName: "Safari", displayTitle: "Release notes"))
                .summaryLine
                == "committed Safari — Release notes 4.8 ms after Command was released"
        )
    }

    @Test func anEmptyListCommitsNothingAndSaysWhy() {
        #expect(
            Self.measurement(.nothingToCommit).summaryLine
                == "committed nothing 4.8 ms after Command was released (the list was empty)"
        )
    }

    @Test func aPressLetGoOfBeforeItsPanelSaysThatInstead() {
        #expect(
            Self.measurement(.pressCalledOff).summaryLine
                == "press called off 4.8 ms after Command was released, "
                + "before the panel appeared"
        )
    }

    /// A window with no title of its own shows its application's name in the
    /// panel, and the line has to agree with the panel. Taking the raw title
    /// here would end the line on a bare em dash.
    @Test(arguments: ["", "   ", "\t\n "])
    func aTitleThatIsNothingFallsBackToTheApplicationName(displayTitle: String) {
        #expect(
            Self.measurement(.committed(appName: "Preview", displayTitle: displayTitle))
                .summaryLine
                == "committed Preview — Preview 4.8 ms after Command was released"
        )
    }

    /// The one that matters most for the log: a title may hold newlines, and
    /// one event printing as two lines breaks both the one-line promise and
    /// any count taken by matching these lines.
    @Test func aTitleHoldingNewlinesStillPrintsAsOneLine() {
        let line = Self.measurement(
            .committed(appName: "Notes", displayTitle: "first\nsecond\r\nthird")
        ).summaryLine
        #expect(!line.contains("\n"))
        #expect(!line.contains("\r"))
        #expect(line == "committed Notes — first second third 4.8 ms after Command was released")
    }

    @Test func tabsAndRunsOfSpacesCollapseToOne() {
        #expect(
            Self.measurement(
                .committed(appName: "Xcode", displayTitle: "  a\t\tb   c  ")
            ).summaryLine
                == "committed Xcode — a b c 4.8 ms after Command was released"
        )
    }

    /// The application name goes through the same flattening. It comes from a
    /// different source than the title, so a title-only fix would leave the
    /// half of the line nobody thought to check.
    @Test func theApplicationNameIsFlattenedTheSameWay() {
        #expect(
            Self.measurement(
                .committed(appName: "Some\nApp", displayTitle: "Window")
            ).summaryLine
                == "committed Some App — Window 4.8 ms after Command was released"
        )
    }

    /// Characters that are neither printable nor whitespace would otherwise
    /// reach whatever terminal is reading the log.
    @Test func controlCharactersBecomeSpacesToo() {
        #expect(
            Self.measurement(
                .committed(appName: "Term", displayTitle: "a\u{0007}b")
            ).summaryLine
                == "committed Term — a b 4.8 ms after Command was released"
        )
    }

    /// A character that prints as nothing leaves a line that reads correctly
    /// and matches nothing, which is the worse of the two failures: a count
    /// taken by matching these lines goes short without saying so. The whole
    /// line is pinned rather than a fragment of it, so the test fails wherever
    /// in the line the character survives.
    @Test func aNameCarryingAZeroWidthSpaceStillMatchesThePlainWording() {
        #expect(
            Self.measurement(
                // U+200B ZERO WIDTH SPACE, written as an escape: pasted in
                // whole it is unreadable here and impossible to maintain.
                .committed(appName: "Safari\u{200B}", displayTitle: "Release notes")
            ).summaryLine
                == "committed Safari — Release notes 4.8 ms after Command was released"
        )
    }

    /// One of these makes a terminal draw the rest of the line backwards, so
    /// the reader is shown a duration running the wrong way round and wording
    /// the app never wrote. A title mixing in a right-to-left script carries
    /// one with nobody meaning it.
    @Test func aTitleReversingTheReadingOrderNeverReachesTheLine() {
        #expect(
            Self.measurement(
                // U+202E RIGHT-TO-LEFT OVERRIDE
                .committed(appName: "Mail", displayTitle: "Inbox\u{202E}draft")
            ).summaryLine
                == "committed Mail — Inbox draft 4.8 ms after Command was released"
        )
    }

    /// The case that fails if the test for an invisible character is ever
    /// loosened from every part of a character to any part of it. This name is
    /// one character built from visible parts and the invisible ones holding
    /// them together, so the looser test would flatten the whole of it away
    /// and leave the line naming nobody.
    @Test func anEmojiHeldTogetherByInvisibleCharactersSurvives() {
        // U+200D ZERO WIDTH JOINER between the three figures.
        let name = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(
            Self.measurement(.committed(appName: name, displayTitle: "Album")).summaryLine
                == "committed \(name) — Album 4.8 ms after Command was released"
        )
    }

    /// A name of nothing but spaces is the one shape the window enumeration's
    /// own fallback does not rule out, and it would leave the line naming
    /// nobody at all.
    @Test func anApplicationNameThatIsNothingIsSaidToBeMissing() {
        #expect(
            Self.measurement(.committed(appName: "  ", displayTitle: "  ")).summaryLine
                == "committed an unnamed application — an unnamed application "
                + "4.8 ms after Command was released"
        )
    }

    /// A name of nothing but characters that take up no space flattens away as
    /// completely as one of nothing but spaces, and has to be said to be
    /// missing the same way. Left alone it would look like a name in the log
    /// and read as an empty one to anything matching the line.
    @Test func anApplicationNameOfNothingVisibleIsSaidToBeMissingTheSameWay() {
        #expect(
            Self.measurement(
                // U+200B ZERO WIDTH SPACE, U+00AD SOFT HYPHEN and U+FEFF ZERO
                // WIDTH NO-BREAK SPACE: none of the three is whitespace.
                .committed(appName: "\u{200B}\u{00AD}\u{FEFF}", displayTitle: "\u{200B}")
            ).summaryLine
                == "committed an unnamed application — an unnamed application "
                + "4.8 ms after Command was released"
        )
    }

    /// Read off the line without arithmetic, and the same in every locale:
    /// how quickly a release was answered is judged on this number.
    @Test func theTimingCarriesExactlyOneDecimalPlace() {
        #expect(
            Self.measurement(.nothingToCommit, elapsed: .microseconds(71251)).summaryLine
                == "committed nothing 71.3 ms after Command was released (the list was empty)"
        )
    }

    /// Committing nothing and never getting as far as a panel are different
    /// events with different answers, so no reading of the log may conflate
    /// them — including a grep that anchors on one and matches the other.
    @Test func theThreeOutcomesAreTellableApartFromTheLineAlone() {
        let outcomes: [CommandReleaseMeasurement.Outcome] = [
            .committed(appName: "Safari", displayTitle: "Release notes"),
            .nothingToCommit,
            .pressCalledOff,
        ]
        let lines = outcomes.map { Self.measurement($0).summaryLine }

        #expect(Set(lines).count == 3)
        for line in lines {
            #expect(lines.filter { $0.hasPrefix(line) }.count == 1)
        }
    }
}
