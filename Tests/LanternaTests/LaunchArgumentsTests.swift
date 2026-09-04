@testable import Lanterna
import Testing

struct LaunchArgumentsTests {
    @Test func absentFlagRequestsNoOverride() throws {
        #expect(try LaunchArguments.sampleCount(from: ["Lanterna"]) == nil)
    }

    @Test(arguments: [
        ["Lanterna", "--sample-count", "3"],
        ["Lanterna", "--sample-count=3"],
    ])
    func bothFlagFormsAreAccepted(arguments: [String]) throws {
        #expect(try LaunchArguments.sampleCount(from: arguments) == 3)
    }

    @Test func zeroIsAValidCount() throws {
        #expect(try LaunchArguments.sampleCount(from: ["Lanterna", "--sample-count", "0"]) == 0)
    }

    @Test func missingValueIsAUsageError() {
        #expect(throws: LaunchArguments.ParseError.missingValue) {
            try LaunchArguments.sampleCount(from: ["Lanterna", "--sample-count"])
        }
    }

    @Test(arguments: ["abc", "3.5", "-1", ""])
    func unusableValueIsAUsageError(value: String) {
        #expect(throws: LaunchArguments.ParseError.invalidValue(value)) {
            try LaunchArguments.sampleCount(from: ["Lanterna", "--sample-count", value])
        }
        #expect(throws: LaunchArguments.ParseError.invalidValue(value)) {
            try LaunchArguments.sampleCount(from: ["Lanterna", "--sample-count=\(value)"])
        }
    }

    @Test func mistypedFlagIsRejected() {
        #expect(throws: LaunchArguments.ParseError.unknownOption("--sample-cout")) {
            try LaunchArguments.sampleCount(from: ["Lanterna", "--sample-cout", "5"])
        }
    }

    @Test(arguments: [
        ["Lanterna", "--sample-count", "3", "--sample-count", "5"],
        ["Lanterna", "--sample-count=3", "--sample-count"],
    ])
    func repeatedFlagIsRejected(arguments: [String]) {
        #expect(throws: LaunchArguments.ParseError.duplicateFlag) {
            try LaunchArguments.sampleCount(from: arguments)
        }
    }

    @Test func singleDashArgumentsInjectedByTheSystemAreIgnored() throws {
        let arguments = ["Lanterna", "-NSDocumentRevisionsDebugMode", "YES"]
        #expect(try LaunchArguments.sampleCount(from: arguments) == nil)
    }

    @Test func flagNeedNotComeFirst() throws {
        let arguments = ["Lanterna", "-ApplePersistenceIgnoreState", "YES", "--sample-count", "3"]
        #expect(try LaunchArguments.sampleCount(from: arguments) == 3)
    }

    @Test func usageLineIsPinnedOnce() {
        #expect(LaunchArguments.usage == "usage: Lanterna [--sample-count N]")
    }

    @Test func errorTextIsTheReasonAlone() {
        #expect("\(LaunchArguments.ParseError.missingValue)" == "--sample-count needs a value")
        #expect(
            "\(LaunchArguments.ParseError.invalidValue("abc"))"
                == "\"abc\" is not a whole number of zero or more"
        )
        #expect(
            "\(LaunchArguments.ParseError.unknownOption("--sample-cout"))"
                == "unknown option \"--sample-cout\""
        )
        #expect(
            "\(LaunchArguments.ParseError.duplicateFlag)"
                == "--sample-count given more than once"
        )
    }
}
