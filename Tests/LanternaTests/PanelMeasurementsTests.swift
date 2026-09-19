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
        gatheredOnDemand: Bool = false,
        becameKey: Bool = false
    ) -> HotkeyMeasurement {
        HotkeyMeasurement(
            combination: combination,
            elapsed: elapsed,
            entryCount: entryCount,
            deliveryDelay: deliveryDelay,
            gatheredOnDemand: gatheredOnDemand,
            becameKey: becameKey
        )
    }

    /// The tail every line carries, whichever way it went. Spelled out here
    /// once so the cases below stay about the segment each of them is for.
    private static let notTakingKeys = "; not taking keys (they reach the frontmost application)"

    /// No run produces this shape today: the delivery reading comes from two
    /// readings of one clock, neither of which can fail, so it is always
    /// there. It stays optional, and tested, so that if the reading ever does
    /// become fallible the line loses a segment instead of losing its meaning.
    @Test func withNothingOptionalTheLineIsTheTimingAlone() {
        #expect(
            Self.measurement().summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)" + Self.notTakingKeys
        )
    }

    /// Whether the panel is taking keys is said on every line and never left
    /// out, both because a reader cannot tell a missing phrase from a build
    /// that never wrote one, and because a phrase that is always there says
    /// which build wrote the line.
    @Test func whetherTheKeyboardArrivedIsAlwaysSaid() {
        #expect(
            Self.measurement(becameKey: true).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries); taking keys"
        )
    }

    @Test func aMeasuredDeliveryFollowsTheTiming() {
        #expect(
            Self.measurement(deliveryDelay: .microseconds(1900)).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"
                + Self.notTakingKeys
        )
    }

    /// A reading taken while the list was still being gathered says more about
    /// the list than about the panel, so it is marked rather than averaged in
    /// with the rest.
    @Test func gatheringOnTheSpotIsCalledOut() {
        #expect(
            Self.measurement(gatheredOnDemand: true).summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries)"
                + "; gathered on the spot (no list held yet)" + Self.notTakingKeys
        )
    }

    @Test func bothOptionalSegmentsKeepTheirOrder() {
        #expect(
            Self.measurement(deliveryDelay: .microseconds(1900), gatheredOnDemand: true)
                .summaryLine
                == "panel shown 4.8 ms after Cmd+Tab (12 entries); delivery 1.9 ms"
                + "; gathered on the spot (no list held yet)" + Self.notTakingKeys
        )
    }

    @Test func theReverseCombinationNamesItself() {
        #expect(
            Self.measurement(combination: .reverse).summaryLine
                == "panel shown 4.8 ms after Shift+Cmd+Tab (12 entries)" + Self.notTakingKeys
        )
    }

    /// Both timings round to one decimal place, so how long the panel took can
    /// be read off the line without arithmetic.
    @Test func timingsCarryExactlyOneDecimalPlace() {
        let line = Self.measurement(
            elapsed: .microseconds(71251),
            deliveryDelay: .zero
        ).summaryLine
        #expect(
            line == "panel shown 71.3 ms after Cmd+Tab (12 entries); delivery 0.0 ms"
                + Self.notTakingKeys
        )
    }
}

/// What the end of an appearance says it was.
///
/// One wording is written every time a panel leaves the screen by a route the
/// user took, and one every time a press is let go of before its panel ever
/// arrived. They are pinned here rather than where the decision is made, so a
/// reword shows up as a failure in the file that owns the wording.
///
/// The ones Command's release has always written predate the trigger being
/// recorded at all, and are the ones no later feature may disturb; the helper
/// below defaults to that trigger so the cases pinning them go on saying
/// nothing about one.
struct PanelExitMeasurementTests {
    /// Letting go of Command by default, so that the cases pinning the three
    /// wordings it has always written say nothing about a trigger and go on
    /// reading as they did. Those three are wording no later feature may
    /// disturb.
    private static func measurement(
        _ outcome: PanelExitMeasurement.Outcome,
        by trigger: PanelExitMeasurement.Trigger = .commandRelease,
        elapsed: Duration = .microseconds(4800)
    ) -> PanelExitMeasurement {
        PanelExitMeasurement(outcome: outcome, trigger: trigger, elapsed: elapsed)
    }

    /// Stands in for whichever window was taken. Every case below but the two
    /// about the identity itself is about how the names are worded, and one
    /// value throughout keeps the identity out of their way.
    private static let someWindow = WindowItem.Identifier(windowID: 42)

    private static func committed(
        appName: String,
        displayTitle: String
    ) -> PanelExitMeasurement.Outcome {
        .committed(appName: appName, displayTitle: displayTitle, id: someWindow)
    }

    @Test func aCommitNamesTheRowItTook() {
        #expect(
            Self.measurement(Self.committed(appName: "Safari", displayTitle: "Release notes"))
                .summaryLine
                == "committed Safari — Release notes (window 42) "
                + "4.8 ms after Command was released"
        )
    }

    /// The identity is what tells two rows apart when the names cannot, so a
    /// line that spelled it any other way would be a line nobody can search.
    /// Swift's own rendering of the identity would read
    /// `(window Identifier(windowID: 42))`, which matches nothing and would
    /// leave a count of rows taken by mistake reading zero for the wrong
    /// reason.
    @Test func twoRowsWithTheSameNamesAreStillToldApartByTheirIdentity() {
        let rows = [WindowItem.Identifier(windowID: 7), WindowItem.Identifier(windowID: 9)]
        let lines = rows.map {
            Self.measurement(
                .committed(appName: "Preview", displayTitle: "Preview", id: $0)
            ).summaryLine
        }
        #expect(
            lines == [
                "committed Preview — Preview (window 7) 4.8 ms after Command was released",
                "committed Preview — Preview (window 9) 4.8 ms after Command was released",
            ]
        )
    }

    /// The timing runs to the end of the line, and a check written against
    /// the previous wording anchors there. Putting the identity before it
    /// rather than after is what keeps that anchor attached.
    @Test func theIdentityGoesBeforeTheTimingSoTheLineStillEndsOnIt() {
        #expect(
            Self.measurement(Self.committed(appName: "Safari", displayTitle: "Notes"))
                .summaryLine
                .hasSuffix(" 4.8 ms after Command was released")
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
            Self.measurement(Self.committed(appName: "Preview", displayTitle: displayTitle))
                .summaryLine
                == "committed Preview — Preview (window 42) 4.8 ms after Command was released"
        )
    }

    /// The one that matters most for the log: a title may hold newlines, and
    /// one event printing as two lines breaks both the one-line promise and
    /// any count taken by matching these lines.
    @Test func aTitleHoldingNewlinesStillPrintsAsOneLine() {
        let line = Self.measurement(
            Self.committed(appName: "Notes", displayTitle: "first\nsecond\r\nthird")
        ).summaryLine
        #expect(!line.contains("\n"))
        #expect(!line.contains("\r"))
        #expect(
            line == "committed Notes — first second third (window 42) "
                + "4.8 ms after Command was released"
        )
    }

    @Test func tabsAndRunsOfSpacesCollapseToOne() {
        #expect(
            Self.measurement(
                Self.committed(appName: "Xcode", displayTitle: "  a\t\tb   c  ")
            ).summaryLine
                == "committed Xcode — a b c (window 42) 4.8 ms after Command was released"
        )
    }

    /// The application name goes through the same flattening. It comes from a
    /// different source than the title, so a title-only fix would leave the
    /// half of the line nobody thought to check.
    @Test func theApplicationNameIsFlattenedTheSameWay() {
        #expect(
            Self.measurement(
                Self.committed(appName: "Some\nApp", displayTitle: "Window")
            ).summaryLine
                == "committed Some App — Window (window 42) 4.8 ms after Command was released"
        )
    }

    /// Characters that are neither printable nor whitespace would otherwise
    /// reach whatever terminal is reading the log.
    @Test func controlCharactersBecomeSpacesToo() {
        #expect(
            Self.measurement(
                Self.committed(appName: "Term", displayTitle: "a\u{0007}b")
            ).summaryLine
                == "committed Term — a b (window 42) 4.8 ms after Command was released"
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
                Self.committed(appName: "Safari\u{200B}", displayTitle: "Release notes")
            ).summaryLine
                == "committed Safari — Release notes (window 42) "
                + "4.8 ms after Command was released"
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
                Self.committed(appName: "Mail", displayTitle: "Inbox\u{202E}draft")
            ).summaryLine
                == "committed Mail — Inbox draft (window 42) 4.8 ms after Command was released"
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
            Self.measurement(Self.committed(appName: name, displayTitle: "Album")).summaryLine
                == "committed \(name) — Album (window 42) 4.8 ms after Command was released"
        )
    }

    /// A name of nothing but spaces is the one shape the window enumeration's
    /// own fallback does not rule out, and it would leave the line naming
    /// nobody at all.
    @Test func anApplicationNameThatIsNothingIsSaidToBeMissing() {
        #expect(
            Self.measurement(Self.committed(appName: "  ", displayTitle: "  ")).summaryLine
                == "committed an unnamed application — an unnamed application (window 42) "
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
                Self.committed(appName: "\u{200B}\u{00AD}\u{FEFF}", displayTitle: "\u{200B}")
            ).summaryLine
                == "committed an unnamed application — an unnamed application (window 42) "
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
    ///
    /// Every pair that can happen is here, not a sample of them. Telling
    /// events apart is a property of the whole set of wordings, so a subset
    /// can only fail to find a clash, never say there is none.
    @Test func everyEndingIsTellableApartFromTheLineAlone() {
        let row = Self.committed(appName: "Safari", displayTitle: "Release notes")
        let lines = [
            Self.measurement(row),
            Self.measurement(row, by: .commitKey(.returnKey)),
            Self.measurement(row, by: .commitKey(.keypadEnter)),
            Self.measurement(.nothingToCommit),
            Self.measurement(.nothingToCommit, by: .commitKey(.returnKey)),
            Self.measurement(.nothingToCommit, by: .commitKey(.keypadEnter)),
            Self.measurement(.pressCalledOff),
            Self.measurement(.cancelled, by: .cancelKey(.commandPeriod)),
            Self.measurement(.cancelled, by: .cancelKey(.escape)),
        ].map(\.summaryLine)

        #expect(Set(lines).count == lines.count)
        for line in lines {
            #expect(lines.filter { $0.hasPrefix(line) }.count == 1)
        }
    }

    /// The two exits a key can bring about, worded so that counting one can
    /// never pick up the other. `cancelled` shares no word with any commit
    /// line, which is what lets `^committed ` and `^cancelled ` be counted
    /// with one pattern each.
    @Test func cancellingSaysNothingAboutARowAndSharesNoStemWithACommit() {
        let byPeriod = Self.measurement(.cancelled, by: .cancelKey(.commandPeriod)).summaryLine
        let byEscape = Self.measurement(.cancelled, by: .cancelKey(.escape)).summaryLine

        #expect(byPeriod == "cancelled 4.8 ms after Cmd+Period")
        #expect(byEscape == "cancelled 4.8 ms after Escape")
        #expect(!byPeriod.hasPrefix("committed"))
        #expect(!byEscape.hasPrefix("committed"))
    }

    /// A commit says which key did it, and the two keys are worded apart.
    /// Which physical key arrived is the evidence for going by key code at
    /// all, and a log that flattened them would throw that evidence away.
    @Test func aCommitByKeyNamesTheKeyAndKeepsTheRow() {
        let row = Self.committed(appName: "Safari", displayTitle: "Release notes")
        #expect(
            Self.measurement(row, by: .commitKey(.returnKey)).summaryLine
                == "committed Safari — Release notes (window 42) 4.8 ms after Return"
        )
        #expect(
            Self.measurement(row, by: .commitKey(.keypadEnter)).summaryLine
                == "committed Safari — Release notes (window 42) 4.8 ms after keypad Enter"
        )
        #expect(
            Self.measurement(.nothingToCommit, by: .commitKey(.returnKey)).summaryLine
                == "committed nothing 4.8 ms after Return (the list was empty)"
        )
    }
}
