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

    @Test func everyErrorCarriesAUsageLine() {
        let errors: [LaunchArguments.ParseError] = [.missingValue, .invalidValue("abc")]
        #expect(errors.allSatisfy { $0.usage.hasPrefix("usage: Lanterna") })
    }
}
