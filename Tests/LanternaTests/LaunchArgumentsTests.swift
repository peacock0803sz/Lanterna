@testable import Lanterna
import Testing

struct LaunchArgumentsTests {
    private static let sampleCount = LaunchArguments.sampleCountFlag
    private static let stopEvery = LaunchArguments.stopMonitorEveryFlag

    @Test func absentFlagsRequestNothing() throws {
        #expect(try LaunchArguments.parse(["Lanterna"]) == LaunchArguments.Options())
    }

    @Test(arguments: [
        ["Lanterna", "--sample-count", "3"],
        ["Lanterna", "--sample-count=3"],
    ])
    func bothFormsOfTheCountAreAccepted(arguments: [String]) throws {
        #expect(try LaunchArguments.parse(arguments).sampleCount == 3)
    }

    @Test(arguments: [
        ["Lanterna", "--stop-monitor-every", "7"],
        ["Lanterna", "--stop-monitor-every=7"],
    ])
    func bothFormsOfThePeriodAreAccepted(arguments: [String]) throws {
        #expect(try LaunchArguments.parse(arguments).stopMonitorEvery == .seconds(7))
    }

    /// The seconds become a `Duration` here and stay one. A number of seconds
    /// carried further as a plain `Int` is a number the next reader has to be
    /// told the unit of, and a timer is where that goes wrong quietly.
    @Test func thePeriodComesBackWithItsUnitAttached() throws {
        let options = try LaunchArguments.parse(["Lanterna", "--stop-monitor-every", "1"])
        #expect(options.stopMonitorEvery == .seconds(1))
        #expect(options.stopMonitorEvery != .milliseconds(1))
    }

    @Test func zeroIsAValidCount() throws {
        #expect(try LaunchArguments.parse(["Lanterna", "--sample-count", "0"]).sampleCount == 0)
    }

    /// Both flags at once, and neither order may change what comes back. They
    /// are read into one value, so a second flag overwriting the first would
    /// show up nowhere else.
    @Test(arguments: [
        ["Lanterna", "--sample-count", "3", "--stop-monitor-every", "7"],
        ["Lanterna", "--stop-monitor-every=7", "--sample-count=3"],
        [
            "Lanterna", "--stop-monitor-every", "7", "-ApplePersistenceIgnoreState", "YES",
            "--sample-count=3",
        ],
    ])
    func bothFlagsTogetherInAnyOrder(arguments: [String]) throws {
        let options = try LaunchArguments.parse(arguments)
        #expect(options.sampleCount == 3)
        #expect(options.stopMonitorEvery == .seconds(7))
    }

    @Test(arguments: [
        ["Lanterna", "--sample-count"],
        ["Lanterna", "--stop-monitor-every"],
    ])
    func missingValueIsAUsageError(arguments: [String]) {
        let flag = arguments[1] == "--sample-count" ? Self.sampleCount : Self.stopEvery
        #expect(throws: LaunchArguments.ParseError.missingValue(flag)) {
            try LaunchArguments.parse(arguments)
        }
    }

    @Test(arguments: ["abc", "3.5", "-1", ""])
    func aCountOutsideItsRangeIsAUsageError(value: String) {
        #expect(throws: LaunchArguments.ParseError.invalidValue(flag: Self.sampleCount, value: value)) {
            try LaunchArguments.parse(["Lanterna", "--sample-count", value])
        }
        #expect(throws: LaunchArguments.ParseError.invalidValue(flag: Self.sampleCount, value: value)) {
            try LaunchArguments.parse(["Lanterna", "--sample-count=\(value)"])
        }
    }

    /// Zero is the difference between the two ranges: a valid count and a
    /// period that would be a way of switching the monitor off rather than a
    /// way of watching it come back.
    @Test(arguments: ["abc", "3.5", "0", "-1", ""])
    func aPeriodOutsideItsRangeIsAUsageError(value: String) {
        #expect(throws: LaunchArguments.ParseError.invalidValue(flag: Self.stopEvery, value: value)) {
            try LaunchArguments.parse(["Lanterna", "--stop-monitor-every", value])
        }
        #expect(throws: LaunchArguments.ParseError.invalidValue(flag: Self.stopEvery, value: value)) {
            try LaunchArguments.parse(["Lanterna", "--stop-monitor-every=\(value)"])
        }
    }

    @Test func mistypedFlagIsRejected() {
        #expect(throws: LaunchArguments.ParseError.unknownOption("--sample-cout")) {
            try LaunchArguments.parse(["Lanterna", "--sample-cout", "5"])
        }
        #expect(throws: LaunchArguments.ParseError.unknownOption("--stop-monitor-ever")) {
            try LaunchArguments.parse(["Lanterna", "--stop-monitor-ever", "5"])
        }
    }

    /// A repeat is refused whichever form the two takes, and refused before
    /// the second one's value is looked at — the second case here has no value
    /// at all, and must still read as a repeat rather than as a flag left
    /// dangling.
    @Test(arguments: [
        ["Lanterna", "--sample-count", "3", "--sample-count", "5"],
        ["Lanterna", "--sample-count=3", "--sample-count"],
    ])
    func aRepeatedCountIsRejected(arguments: [String]) {
        #expect(throws: LaunchArguments.ParseError.duplicateFlag(Self.sampleCount)) {
            try LaunchArguments.parse(arguments)
        }
    }

    @Test(arguments: [
        ["Lanterna", "--stop-monitor-every", "7", "--stop-monitor-every", "9"],
        ["Lanterna", "--stop-monitor-every=7", "--stop-monitor-every"],
    ])
    func aRepeatedPeriodIsRejected(arguments: [String]) {
        #expect(throws: LaunchArguments.ParseError.duplicateFlag(Self.stopEvery)) {
            try LaunchArguments.parse(arguments)
        }
    }

    /// One flag twice is a repeat; two different flags are not. With the
    /// values gathered under one roof, telling those apart is the thing that
    /// could most easily have been got wrong.
    @Test func oneFlagDoesNotCountAsARepeatOfTheOther() throws {
        let arguments = ["Lanterna", "--sample-count", "3", "--stop-monitor-every", "7"]
        #expect(try LaunchArguments.parse(arguments).sampleCount == 3)
    }

    @Test func singleDashArgumentsInjectedByTheSystemAreIgnored() throws {
        let arguments = ["Lanterna", "-NSDocumentRevisionsDebugMode", "YES"]
        #expect(try LaunchArguments.parse(arguments) == LaunchArguments.Options())
    }

    @Test func flagNeedNotComeFirst() throws {
        let arguments = ["Lanterna", "-ApplePersistenceIgnoreState", "YES", "--sample-count", "3"]
        #expect(try LaunchArguments.parse(arguments).sampleCount == 3)
    }

    @Test func usageLineIsPinnedOnce() {
        #expect(
            LaunchArguments.usage
                == "usage: Lanterna [--sample-count N] [--stop-monitor-every SECONDS]"
        )
    }

    /// The range is spelled out and differs between the flags, which is why
    /// the name is there at all: told only which flag was wrong, a reader
    /// still would not know what it would have taken.
    @Test func errorTextIsTheReasonAlone() {
        #expect(
            "\(LaunchArguments.ParseError.missingValue(Self.stopEvery))"
                == "--stop-monitor-every needs a value"
        )
        #expect(
            "\(LaunchArguments.ParseError.invalidValue(flag: Self.sampleCount, value: "abc"))"
                == "\"abc\" is not a whole number of zero or more (--sample-count)"
        )
        #expect(
            "\(LaunchArguments.ParseError.invalidValue(flag: Self.stopEvery, value: "0"))"
                == "\"0\" is not a whole number of one or more (--stop-monitor-every)"
        )
        #expect(
            "\(LaunchArguments.ParseError.unknownOption("--sample-cout"))"
                == "unknown option \"--sample-cout\""
        )
        #expect(
            "\(LaunchArguments.ParseError.duplicateFlag(Self.sampleCount))"
                == "--sample-count given more than once"
        )
    }
}
